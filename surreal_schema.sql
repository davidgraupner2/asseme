-- SurrealDB Multitenant User System with Graph Relationships
-- This schema supports users belonging to multiple tenants with different roles

-- ======================================================================
-- CLEANUP SECTION - Remove existing tables and functions
-- This allows the schema to be run multiple times safely
-- ======================================================================

-- Remove existing functions
REMOVE FUNCTION IF EXISTS fn::get_user_tenants;
REMOVE FUNCTION IF EXISTS fn::get_tenant_members;
REMOVE FUNCTION IF EXISTS fn::user_has_permission;
REMOVE FUNCTION IF EXISTS fn::current_user_has_permission;
REMOVE FUNCTION IF EXISTS fn::tenant_signup;
REMOVE FUNCTION IF EXISTS fn::invite_user_to_tenant;
REMOVE FUNCTION IF EXISTS fn::accept_invitation;

-- Remove existing indexes
REMOVE INDEX IF EXISTS user_email_idx ON TABLE user;
REMOVE INDEX IF EXISTS tenant_slug_idx ON TABLE tenant;
REMOVE INDEX IF EXISTS role_slug_idx ON TABLE role;
REMOVE INDEX IF EXISTS invitation_token_idx ON TABLE invitation;

-- Remove existing tables (in reverse dependency order)
REMOVE TABLE IF EXISTS audit_log;
REMOVE TABLE IF EXISTS invitation;
REMOVE TABLE IF EXISTS member_of;
REMOVE TABLE IF EXISTS role;
REMOVE TABLE IF EXISTS tenant;
REMOVE TABLE IF EXISTS user;

-- ======================================================================
-- SCHEMA DEFINITION STARTS HERE
-- ======================================================================

-- User table - Core user information  
DEFINE TABLE user SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE $auth.id = id OR 'user.read' IN $auth.current_permissions OR '*' IN $auth.current_permissions,
        FOR create WHERE 'user.create' IN $auth.current_permissions OR '*' IN $auth.current_permissions,
        FOR update WHERE $auth.id = id OR 'user.update' IN $auth.current_permissions OR '*' IN $auth.current_permissions,
        FOR delete WHERE 'user.delete' IN $auth.current_permissions OR '*' IN $auth.current_permissions;

DEFINE FIELD id ON TABLE user TYPE record<user>;
DEFINE FIELD email ON TABLE user TYPE string ASSERT string::is::email($value);
DEFINE FIELD password ON TABLE user TYPE string;
DEFINE FIELD name ON TABLE user TYPE string;
DEFINE FIELD avatar ON TABLE user TYPE option<string>;
DEFINE FIELD created_at ON TABLE user TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON TABLE user TYPE datetime DEFAULT time::now();
DEFINE FIELD last_login ON TABLE user TYPE option<datetime>;
DEFINE FIELD email_verified ON TABLE user TYPE bool DEFAULT false;
DEFINE FIELD status ON TABLE user TYPE string DEFAULT 'active' ASSERT $value IN ['active', 'inactive', 'suspended'];
DEFINE FIELD current_tenant ON TABLE user TYPE option<record<tenant>>; -- Current tenant context
DEFINE FIELD current_permissions ON TABLE user TYPE array<string> DEFAULT []; -- Current permissions for current tenant
DEFINE FIELD metadata ON TABLE user TYPE object DEFAULT {}; -- Additional flexible data per user

-- Create unique index on email
DEFINE INDEX user_email_idx ON TABLE user COLUMNS email UNIQUE;

-- Tenant table - Organization/Company information
DEFINE TABLE tenant SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE $this.id = $auth.current_tenant AND ('tenant.read' IN $auth.current_permissions OR '*' IN $auth.current_permissions),
        FOR create WHERE 'tenant.create' IN $auth.current_permissions OR '*' IN $auth.current_permissions,
        FOR update WHERE $this.id = $auth.current_tenant AND ('tenant.update' IN $auth.current_permissions OR '*' IN $auth.current_permissions),
        FOR delete WHERE $this.id = $auth.current_tenant AND ('tenant.delete' IN $auth.current_permissions OR '*' IN $auth.current_permissions);

DEFINE FIELD id ON TABLE tenant TYPE record<tenant>;
DEFINE FIELD name ON TABLE tenant TYPE string;
DEFINE FIELD slug ON TABLE tenant TYPE string ASSERT string::len($value) > 2;
DEFINE FIELD description ON TABLE tenant TYPE option<string>;
DEFINE FIELD logo ON TABLE tenant TYPE option<string>;
DEFINE FIELD plan ON TABLE tenant TYPE string DEFAULT 'basic' ASSERT $value IN ['basic', 'pro', 'enterprise'];
DEFINE FIELD status ON TABLE tenant TYPE string DEFAULT 'active' ASSERT $value IN ['active', 'inactive', 'suspended', 'trial'];
DEFINE FIELD created_at ON TABLE tenant TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON TABLE tenant TYPE datetime DEFAULT time::now();
DEFINE FIELD settings ON TABLE tenant TYPE object DEFAULT {}; -- Additional flexible settings per tenant
DEFINE FIELD billing_info ON TABLE tenant TYPE object DEFAULT {}; -- Billing related data
DEFINE FIELD features ON TABLE tenant TYPE array<string> DEFAULT []; -- Enabled features for this tenant

-- Create unique index on slug
DEFINE INDEX tenant_slug_idx ON TABLE tenant COLUMNS slug UNIQUE;

-- Role definitions table - Define available roles in the system
DEFINE TABLE role SCHEMAFULL;
DEFINE FIELD id ON TABLE role TYPE record<role>;
DEFINE FIELD name ON TABLE role TYPE string;
DEFINE FIELD slug ON TABLE role TYPE string;
DEFINE FIELD description ON TABLE role TYPE option<string>;
DEFINE FIELD permissions ON TABLE role TYPE array<string> DEFAULT []; -- Array of permission strings
DEFINE FIELD is_system_role ON TABLE role TYPE bool DEFAULT false; -- System roles vs custom roles
DEFINE FIELD created_at ON TABLE role TYPE datetime DEFAULT time::now();

-- Create unique index on role slug
DEFINE INDEX role_slug_idx ON TABLE role COLUMNS slug UNIQUE;

-- Graph relationship: User membership in tenants with roles
-- This is the key relationship that connects users to tenants with specific roles
DEFINE TABLE member_of SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE fn::user_has_permission($auth.id, out, 'member.read') OR in = $auth.id,
        FOR create WHERE fn::user_has_permission($auth.id, out, 'member.create'),
        FOR update WHERE fn::user_has_permission($auth.id, out, 'member.update') OR in = $auth.id,
        FOR delete WHERE fn::user_has_permission($auth.id, out, 'member.delete');

DEFINE FIELD id ON TABLE member_of TYPE record<member_of>;
DEFINE FIELD in ON TABLE member_of TYPE record<user>;
DEFINE FIELD out ON TABLE member_of TYPE record<tenant>;
DEFINE FIELD role ON TABLE member_of TYPE record<role>;
DEFINE FIELD joined_at ON TABLE member_of TYPE datetime DEFAULT time::now();
DEFINE FIELD invited_at ON TABLE member_of TYPE option<datetime>;
DEFINE FIELD invited_by ON TABLE member_of TYPE option<record<user>>;
DEFINE FIELD status ON TABLE member_of TYPE string DEFAULT 'active' ASSERT $value IN ['active', 'inactive', 'invited', 'suspended'];
DEFINE FIELD user_settings ON TABLE member_of TYPE object DEFAULT {}; -- User-specific settings per tenant
DEFINE FIELD tenant_metadata ON TABLE member_of TYPE object DEFAULT {}; -- Additional data about this membership

-- Invitation system - For pending invitations
DEFINE TABLE invitation SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE fn::user_has_permission($auth.id, tenant, 'invitation.read') OR invited_by = $auth.id,
        FOR create WHERE fn::user_has_permission($auth.id, tenant, 'invitation.send'),
        FOR update WHERE fn::user_has_permission($auth.id, tenant, 'invitation.manage') OR invited_by = $auth.id,
        FOR delete WHERE fn::user_has_permission($auth.id, tenant, 'invitation.manage');

DEFINE FIELD id ON TABLE invitation TYPE record<invitation>;
DEFINE FIELD email ON TABLE invitation TYPE string ASSERT string::is::email($value);
DEFINE FIELD tenant ON TABLE invitation TYPE record<tenant>;
DEFINE FIELD role ON TABLE invitation TYPE record<role>;
DEFINE FIELD invited_by ON TABLE invitation TYPE record<user>;
DEFINE FIELD token ON TABLE invitation TYPE string;
DEFINE FIELD expires_at ON TABLE invitation TYPE datetime;
DEFINE FIELD created_at ON TABLE invitation TYPE datetime DEFAULT time::now();
DEFINE FIELD accepted_at ON TABLE invitation TYPE option<datetime>;
DEFINE FIELD status ON TABLE invitation TYPE string DEFAULT 'pending' ASSERT $value IN ['pending', 'accepted', 'expired', 'cancelled'];
DEFINE FIELD message ON TABLE invitation TYPE option<string>; -- Custom invitation message

-- Create unique index on invitation token
DEFINE INDEX invitation_token_idx ON TABLE invitation COLUMNS token UNIQUE;

-- Audit log for tracking user actions within tenants
DEFINE TABLE audit_log SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE fn::user_has_permission($auth.id, tenant, 'audit.read'),
        FOR create WHERE true, -- Allow system to create audit logs
        FOR update WHERE false, -- Audit logs should be immutable
        FOR delete WHERE fn::user_has_permission($auth.id, tenant, 'audit.delete');

DEFINE FIELD id ON TABLE audit_log TYPE record<audit_log>;
DEFINE FIELD user ON TABLE audit_log TYPE record<user>;
DEFINE FIELD tenant ON TABLE audit_log TYPE record<tenant>;
DEFINE FIELD action ON TABLE audit_log TYPE string; -- e.g., 'user.created', 'role.changed', etc.
DEFINE FIELD resource_type ON TABLE audit_log TYPE option<string>; -- Type of resource affected
DEFINE FIELD resource_id ON TABLE audit_log TYPE option<string>; -- ID of resource affected
DEFINE FIELD details ON TABLE audit_log TYPE object DEFAULT {}; -- Additional action details
DEFINE FIELD ip_address ON TABLE audit_log TYPE option<string>;
DEFINE FIELD user_agent ON TABLE audit_log TYPE option<string>;
DEFINE FIELD timestamp ON TABLE audit_log TYPE datetime DEFAULT time::now();

-- Insert default system roles
INSERT INTO role (name, slug, description, permissions, is_system_role) VALUES
    ('Super Admin', 'super_admin', 'Full system access across all tenants', ['*'], true),
    ('Admin', 'admin', 'Full access within a tenant', [
        'user.create', 'user.read', 'user.update', 'user.delete',
        'tenant.read', 'tenant.update',
        'role.assign', 'role.revoke',
        'invitation.send', 'invitation.manage'
    ], true),
    ('Manager', 'manager', 'Management access within a tenant', [
        'user.read', 'user.update',
        'tenant.read',
        'invitation.send'
    ], true),
    ('User', 'user', 'Standard user access', [
        'tenant.read',
        'profile.read', 'profile.update'
    ], true),
    ('Viewer', 'viewer', 'Read-only access', [
        'tenant.read'
    ], true);

-- Example queries and functions

-- Function to get all tenants for a user with their roles
DEFINE FUNCTION fn::get_user_tenants($user_id: record<user>) {
    RETURN SELECT 
        out.* as tenant,
        role.* as role,
        joined_at,
        status,
        user_settings,
        tenant_metadata
    FROM member_of 
    WHERE in = $user_id AND status = 'active';
};

-- Function to get all users in a tenant with their roles
DEFINE FUNCTION fn::get_tenant_members($tenant_id: record<tenant>) {
    RETURN SELECT 
        in.* as user,
        role.* as role,
        joined_at,
        status,
        user_settings,
        tenant_metadata
    FROM member_of 
    WHERE out = $tenant_id AND status = 'active';
};

-- Function to check if user has specific permission in tenant
DEFINE FUNCTION fn::user_has_permission($user_id: record<user>, $tenant_id: record<tenant>, $permission: string) {
    -- Handle null/undefined cases
    IF !$user_id OR !$tenant_id OR !$permission {
        RETURN false;
    };
    
    LET $membership = SELECT * FROM member_of WHERE in = $user_id AND out = $tenant_id AND status = 'active';
    IF !$membership {
        RETURN false;
    };
    LET $role = SELECT * FROM role WHERE id = $membership[0].role;
    RETURN $permission IN $role[0].permissions OR '*' IN $role[0].permissions;
};

-- Function to check if current authenticated user has permission (for schema-level permissions)
DEFINE FUNCTION fn::current_user_has_permission($tenant_id: record<tenant>, $permission: string) {
    -- $auth is automatically available in SurrealDB permissions context
    IF !$auth OR !$auth.id {
        RETURN false;
    };
    RETURN fn::user_has_permission($auth.id, $tenant_id, $permission);
};

-- Function to validate user credentials for tenant context
DEFINE FUNCTION fn::validate_user_for_tenant($email: string, $password: string, $tenant_id: record<tenant>) {
    -- Authenticate user
    LET $user = SELECT * FROM user WHERE email = $email;
    IF !$user {
        THROW "Invalid credentials";
    };
    
    -- Verify password
    IF !crypto::argon2::compare($password, $user[0].password) {
        THROW "Invalid credentials";
    };
    
    -- Verify user belongs to tenant
    LET $membership = SELECT * FROM member_of 
        WHERE in = $user[0].id AND out = $tenant_id AND status = 'active';
    IF !$membership {
        THROW "User not authorized for this tenant";
    };
    
    -- Get role and permissions
    LET $role = SELECT * FROM role WHERE id = $membership[0].role;
    
    -- Update user context and last login
    UPDATE user SET 
        last_login = time::now(),
        current_tenant = $tenant_id,
        current_permissions = $role[0].permissions
    WHERE id = $user[0].id;
    
    -- Return user data for authentication
    RETURN {
        success: true,
        user: {
            id: $user[0].id,
            email: $user[0].email,
            name: $user[0].name,
            tenant_id: $tenant_id,
            role: $role[0],
            permissions: $role[0].permissions,
            membership: $membership[0]
        },
        message: "Validation successful"
    };
};

-- Function to switch user's current tenant context
DEFINE FUNCTION fn::switch_tenant($user_id: record<user>, $tenant_id: record<tenant>) {
    -- Verify user belongs to tenant
    LET $membership = SELECT * FROM member_of 
        WHERE in = $user_id AND out = $tenant_id AND status = 'active';
    IF !$membership {
        THROW "User not authorized for this tenant";
    };
    
    -- Get permissions for this tenant
    LET $role = SELECT * FROM role WHERE id = $membership[0].role;
    
    -- Update user's current context
    UPDATE user SET 
        current_tenant = $tenant_id,
        current_permissions = $role[0].permissions
    WHERE id = $user_id;
    
    RETURN { 
        success: true, 
        tenant: $tenant_id, 
        permissions: $role[0].permissions,
        message: "Tenant context switched successfully"
    };
};

-- Function to create a new tenant with an admin user (tenant signup)
DEFINE FUNCTION fn::tenant_signup(
    $user_email: string,
    $user_password: string,
    $user_name: string,
    $tenant_name: string,
    $tenant_description: option<string>,
    $user_metadata: option<object>,
    $tenant_settings: option<object>
) {
    -- Validate inputs
    IF !string::is::email($user_email) {
        THROW "Invalid email format";
    };
    
    IF string::len($user_password) < 8 {
        THROW "Password must be at least 8 characters long";
    };
    
    IF string::len($tenant_name) < 2 {
        THROW "Tenant name must be at least 2 characters long";
    };
    
    -- Check if email already exists
    LET $existing_user = SELECT id FROM user WHERE email = $user_email;
    IF $existing_user {
        THROW "User with this email already exists";
    };
    
    -- Generate unique slug from tenant name
    LET $base_slug = string::lowercase(string::replace(string::replace(string::trim($tenant_name), ' ', '-'), '[^a-z0-9-]', ''));
    LET $final_slug = $base_slug;
    
    -- Check if base slug exists, if so, try with numbers
    LET $existing_tenant = SELECT id FROM tenant WHERE slug = $base_slug;
    IF $existing_tenant {
        -- Try numbered versions until we find a unique one
        FOR $i IN 1..100 {
            LET $test_slug = string::concat($base_slug, '-', <string>$i);
            LET $check_tenant = SELECT id FROM tenant WHERE slug = $test_slug;
            IF !$check_tenant {
                LET $final_slug = $test_slug;
                BREAK;
            };
        };
    };
    
    -- Get super admin role
    LET $admin_role = SELECT id FROM role WHERE slug = 'admin';
    IF !$admin_role {
        THROW "Admin role not found";
    };
    
    -- Create the user
    LET $new_user = CREATE user SET
        email = $user_email,
        password = crypto::argon2::generate($user_password),
        name = $user_name,
        email_verified = true,
        status = 'active',
        metadata = $user_metadata OR {};
    
    -- Create the tenant
    LET $new_tenant = CREATE tenant SET
        name = $tenant_name,
        slug = $final_slug,
        description = $tenant_description,
        plan = 'basic',
        status = 'active',
        settings = $tenant_settings OR {},
        billing_info = {},
        features = ['basic_dashboard', 'user_management'];
    
    -- Create the membership relationship with super admin role
    LET $membership = CREATE member_of SET
        in = $new_user[0].id,
        out = $new_tenant[0].id,
        role = $admin_role[0].id,
        status = 'active',
        user_settings = {
            theme: 'light',
            notifications: true,
            dashboard_layout: 'default'
        },
        tenant_metadata = {
            is_founder: true,
            employee_id: 'FOUNDER-001'
        };
    
    -- Log the signup action
    CREATE audit_log SET
        user = $new_user[0].id,
        tenant = $new_tenant[0].id,
        action = 'tenant.signup',
        resource_type = 'tenant',
        resource_id = <string>$new_tenant[0].id,
        details = {
            user_email: $user_email,
            tenant_name: $tenant_name,
            tenant_slug: $final_slug,
            role: 'admin'
        },
        timestamp = time::now();
    
    -- Return the created entities
    RETURN {
        success: true,
        user: $new_user[0],
        tenant: $new_tenant[0],
        membership: $membership,
        message: "Tenant and admin user created successfully"
    };
};

-- Function to invite a user to a tenant
DEFINE FUNCTION fn::invite_user_to_tenant(
    $inviter_id: record<user>,
    $tenant_id: record<tenant>,
    $email: string,
    $role_slug: string,
    $message: option<string>
) {
    -- Validate email
    IF !string::is::email($email) {
        THROW "Invalid email format";
    };
    
    -- Check if inviter has permission to invite users
    LET $can_invite = fn::user_has_permission($inviter_id, $tenant_id, 'invitation.send');
    IF !$can_invite {
        THROW "User does not have permission to send invitations";
    };
    
    -- Get the role
    LET $role = SELECT id FROM role WHERE slug = $role_slug;
    IF !$role {
        THROW "Role not found";
    };
    
    -- Check if user is already a member
    LET $existing_user = SELECT id FROM user WHERE email = $email;
    IF $existing_user {
        LET $existing_membership = SELECT * FROM member_of 
            WHERE in = $existing_user[0].id AND out = $tenant_id AND status = 'active';
        IF $existing_membership {
            THROW "User is already a member of this tenant";
        };
    };
    
    -- Check for existing pending invitation
    LET $existing_invitation = SELECT * FROM invitation 
        WHERE email = $email AND tenant = $tenant_id AND status = 'pending';
    IF $existing_invitation {
        THROW "Invitation already sent to this email for this tenant";
    };
    
    -- Generate invitation token
    LET $token = crypto::md5(string::concat($email, <string>$tenant_id, <string>time::now()));
    
    -- Create invitation
    LET $invitation = CREATE invitation SET
        email = $email,
        tenant = $tenant_id,
        role = $role[0].id,
        invited_by = $inviter_id,
        token = $token,
        expires_at = time::now() + 7d, -- 7 days expiry
        message = $message,
        status = 'pending';
    
    -- Log the invitation
    CREATE audit_log SET
        user = $inviter_id,
        tenant = $tenant_id,
        action = 'invitation.sent',
        resource_type = 'invitation',
        resource_id = <string>$invitation.id,
        details = {
            invited_email: $email,
            role: $role_slug
        };
    
    RETURN {
        success: true,
        invitation: $invitation,
        message: "Invitation sent successfully"
    };
};

-- Function to accept an invitation
DEFINE FUNCTION fn::accept_invitation(
    $token: string,
    $user_email: string,
    $user_password: option<string>,
    $user_name: option<string>
) {
    -- Find the invitation
    LET $invitation = SELECT * FROM invitation WHERE token = $token AND status = 'pending';
    IF !$invitation {
        THROW "Invalid or expired invitation token";
    };
    
    -- Check if invitation has expired
    IF $invitation[0].expires_at < time::now() {
        UPDATE invitation SET status = 'expired' WHERE id = $invitation[0].id;
        THROW "Invitation has expired";
    };
    
    -- Check if email matches
    IF $invitation[0].email != $user_email {
        THROW "Email does not match invitation";
    };
    
    -- Get or create user
    LET $user = SELECT * FROM user WHERE email = $user_email;
    
    IF !$user {
        -- Create new user if they don't exist
        IF !$user_password OR !$user_name {
            THROW "Password and name are required for new users";
        };
        
        LET $new_user = CREATE user SET
            email = $user_email,
            password = crypto::argon2::generate($user_password),
            name = $user_name,
            email_verified = true,
            status = 'active',
            metadata = {};
        
        LET $user = $new_user;
    } ELSE {
        LET $user = $user[0];
    };
    
    -- Create membership
    CREATE member_of SET
        in = $user.id,
        out = $invitation[0].tenant,
        role = $invitation[0].role,
        status = 'active',
        invited_at = $invitation[0].created_at,
        invited_by = $invitation[0].invited_by,
        user_settings = {},
        tenant_metadata = {};
    
    -- Update invitation status
    UPDATE invitation SET 
        status = 'accepted',
        accepted_at = time::now()
    WHERE id = $invitation[0].id;
    
    -- Log the acceptance
    CREATE audit_log SET
        user = $user.id,
        tenant = $invitation[0].tenant,
        action = 'invitation.accepted',
        resource_type = 'invitation',
        resource_id = <string>$invitation[0].id,
        details = {
            user_email: $user_email
        };
    
    RETURN {
        success: true,
        user: $user,
        tenant: $invitation[0].tenant,
        message: "Invitation accepted successfully"
    };
};

-- Example data insertion

-- Create a sample tenant using the tenant signup function
LET $signup_result = fn::tenant_signup(
    "admin@newcompany.com",           -- user email
    "securepassword123",              -- user password
    "John Administrator",             -- user name
    "New Company Inc",                -- tenant name
    "A new innovative company",       -- tenant description (optional)
    {                                 -- user metadata (optional)
        department: "Administration",
        hire_date: "2025-10-19",
        phone: "+1-555-0123"
    },
    {                                 -- tenant settings (optional)
        timezone: "UTC",
        currency: "USD",
        language: "en"
    }
);

-- Create additional sample data for testing
LET $tenant1 = CREATE tenant SET 
    name = "Acme Corporation",
    slug = "acme-corp",
    description = "Leading software company",
    plan = "enterprise";

-- Create sample users
LET $user1 = CREATE user SET 
    email = "john@example.com",
    password = crypto::argon2::generate("password123"),
    name = "John Doe",
    metadata = {
        department: "Engineering",
        hire_date: "2023-01-15"
    };

LET $user2 = CREATE user SET 
    email = "jane@example.com",
    password = crypto::argon2::generate("password123"),
    name = "Jane Smith",
    metadata = {
        department: "Marketing",
        hire_date: "2023-02-01"
    };

-- Get role IDs
LET $admin_role = SELECT id FROM role WHERE slug = 'admin';
LET $user_role = SELECT id FROM role WHERE slug = 'user';

-- Create memberships
CREATE member_of SET 
    in = $user1[0].id,
    out = $tenant1[0].id,
    role = $admin_role[0].id,
    user_settings = {
        theme: "dark",
        notifications: true
    },
    tenant_metadata = {
        department: "Engineering",
        employee_id: "ENG001"
    };

CREATE member_of SET 
    in = $user2[0].id,
    out = $tenant1[0].id,
    role = $user_role[0].id,
    user_settings = {
        theme: "light",
        notifications: false
    },
    tenant_metadata = {
        department: "Marketing",
        employee_id: "MKT001"
    };

-- Example usage of the tenant signup function:
-- 
-- LET $result = fn::tenant_signup(
--     "founder@startup.com",
--     "strongpassword",
--     "Jane Founder",
--     "Startup Company",
--     "An innovative tech startup",
--     { department: "Executive" },
--     { timezone: "PST", currency: "USD" }
-- );

-- Example usage of invitation functions:
--
-- Send invitation:
-- LET $invite_result = fn::invite_user_to_tenant(
--     user:abc123,                    -- inviter user ID
--     tenant:xyz789,                  -- tenant ID
--     "newuser@example.com",          -- email to invite
--     "user",                         -- role slug
--     "Welcome to our team!"          -- optional message
-- );
--
-- Accept invitation:
-- LET $accept_result = fn::accept_invitation(
--     "invitation_token_here",        -- invitation token
--     "newuser@example.com",          -- user email
--     "password123",                  -- password (for new users)
--     "New User Name"                 -- name (for new users)
-- );

-- Example queries to test the system

-- Get all tenants for user1
-- fn::get_user_tenants($user1.id);

-- Get all members of tenant1
-- fn::get_tenant_members($tenant1.id);

-- Check if user1 has 'user.create' permission in tenant1
-- fn::user_has_permission($user1.id, $tenant1.id, 'user.create');

-- Complex query: Get users with admin role across all tenants
-- SELECT 
--     member.in.name as user_name,
--     member.in.email as user_email,
--     member.out.name as tenant_name,
--     member.role.name as role_name
-- FROM member_of as member
-- WHERE member.role.slug = 'admin' AND member.status = 'active';

-- Query to find all permissions a user has across all their tenants
-- SELECT 
--     tenant.name as tenant_name,
--     role.name as role_name,
--     role.permissions as permissions
-- FROM member_of as membership
-- RELATE membership.out as tenant
-- RELATE membership.role as role
-- WHERE membership.in = $user1.id AND membership.status = 'active';