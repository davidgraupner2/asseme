-- Enhanced Multi-Tenant Schema with MSP Support
-- This schema supports a hierarchical tenant structure:
-- Super Admins > MSP Admins > Customer Admins > Users

-- Initial Super Admin created
-- Email: super@admin.com
-- Password: TempPassword123!
-- Status: password_must_change = true

-- ======================================================================
-- CLEANUP SECTION - Remove existing database and namespace
-- This allows the schema to be run multiple times safely
-- ======================================================================
DEFINE NAMESPACE IF NOT EXISTS asseme COMMENT "Assest Me - primary namespace";
USE NS asseme;
REMOVE DATABASE IF EXISTS msp;
DEFINE DATABASE msp COMMENT "Asset Me - MSP Primary Database"; 
USE DB msp;

-- Enhanced Role definitions with MSP hierarchy
DEFINE TABLE role SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE fn::has_permission(<string>$auth.id, 'role.view_all', NONE) OR fn::has_permission(<string>$auth.id, 'role.view_own_tenant', NONE)
        FOR create, update, delete WHERE fn::has_permission(<string>$auth.id, 'system.manage', NONE);
DEFINE FIELD name ON TABLE role TYPE string ASSERT $value != NONE;
DEFINE FIELD description ON TABLE role TYPE string;
DEFINE FIELD level ON TABLE role TYPE number ASSERT $value >= 1 AND $value <= 5;
DEFINE FIELD permissions ON TABLE role TYPE array<string>;
DEFINE FIELD created_at ON TABLE role TYPE datetime DEFAULT time::now();

-- Enhanced Tenant table with MSP support
DEFINE TABLE tenant SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE fn::has_permission(<string>$auth.id, 'tenant.view_all', NONE) OR 
                        fn::has_permission(<string>$auth.id, 'tenant.view_own', <string>id) OR
                        fn::has_permission(<string>$auth.id, 'tenant.view_customers', <string>id)
        FOR create WHERE fn::has_permission(<string>$auth.id, 'tenant.create', NONE)
        FOR update WHERE fn::has_permission(<string>$auth.id, 'tenant.manage_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'tenant.update_own', <string>id) OR
                        fn::has_permission(<string>$auth.id, 'tenant.update_customers', <string>id)
        FOR delete WHERE fn::has_permission(<string>$auth.id, 'tenant.delete', NONE);
DEFINE FIELD name ON TABLE tenant TYPE string ASSERT $value != NONE;
DEFINE FIELD slug ON TABLE tenant TYPE string ASSERT $value != NONE;
DEFINE FIELD tenant_type ON TABLE tenant TYPE string ASSERT $value IN ['super_admin', 'msp', 'customer'] DEFAULT 'customer';
DEFINE FIELD parent_tenant ON TABLE tenant TYPE option<record<tenant>>;
DEFINE FIELD msp_tenant ON TABLE tenant TYPE option<record<tenant>>;
DEFINE FIELD contact_email ON TABLE tenant TYPE string;
DEFINE FIELD contact_phone ON TABLE tenant TYPE option<string>;
DEFINE FIELD billing_enabled ON TABLE tenant TYPE bool DEFAULT true;
DEFINE FIELD billing_responsibility ON TABLE tenant TYPE string ASSERT $value IN ['self', 'msp', 'parent'] DEFAULT 'self';
DEFINE FIELD status ON TABLE tenant TYPE string ASSERT $value IN ['active', 'suspended', 'inactive'] DEFAULT 'active';
DEFINE FIELD settings ON TABLE tenant TYPE object DEFAULT {};
DEFINE FIELD created_at ON TABLE tenant TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON TABLE tenant TYPE datetime DEFAULT time::now();

-- User table with enhanced tenant relationships and security
DEFINE TABLE user SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE $auth.id = id OR 
                        fn::has_permission(<string>$auth.id, 'user.view_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'user.view_own_tenant', <string>primary_tenant) OR
                        fn::has_permission(<string>$auth.id, 'user.view_customers', <string>primary_tenant)
        FOR create WHERE fn::has_permission(<string>$auth.id, 'user.create_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'user.create_own_tenant', <string>primary_tenant) OR
                        fn::has_permission(<string>$auth.id, 'user.create_customers', <string>primary_tenant)
        FOR update WHERE $auth.id = id OR
                        fn::has_permission(<string>$auth.id, 'user.update_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'user.update_own_tenant', <string>primary_tenant) OR
                        fn::has_permission(<string>$auth.id, 'user.update_customers', <string>primary_tenant)
        FOR delete WHERE fn::has_permission(<string>$auth.id, 'user.delete_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'user.delete_own_tenant', <string>primary_tenant) OR
                        fn::has_permission(<string>$auth.id, 'user.delete_customers', <string>primary_tenant);
DEFINE FIELD email ON TABLE user TYPE string ASSERT string::is::email($value);
DEFINE FIELD password_hash ON TABLE user TYPE string ASSERT $value != NONE
    PERMISSIONS FOR select WHERE $auth.id = id;
DEFINE FIELD password_must_change ON TABLE user TYPE bool DEFAULT false;
DEFINE FIELD first_name ON TABLE user TYPE string;
DEFINE FIELD last_name ON TABLE user TYPE string;
DEFINE FIELD phone ON TABLE user TYPE option<string>;
DEFINE FIELD primary_tenant ON TABLE user TYPE record<tenant>;
DEFINE FIELD accessible_tenants ON TABLE user TYPE array<record<tenant>> DEFAULT [];
DEFINE FIELD is_active ON TABLE user TYPE bool DEFAULT true;
DEFINE FIELD last_login ON TABLE user TYPE option<datetime>;
DEFINE FIELD password_changed_at ON TABLE user TYPE option<datetime>;
DEFINE FIELD created_at ON TABLE user TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON TABLE user TYPE datetime DEFAULT time::now();

-- User-Role relationship with tenant context
DEFINE TABLE user_role SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE $auth.id = user OR
                        fn::has_permission(<string>$auth.id, 'role.view_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'role.view_own_tenant', <string>tenant)
        FOR create, update WHERE fn::has_permission(<string>$auth.id, 'role.assign_all', NONE) OR
                               fn::has_permission(<string>$auth.id, 'role.assign_own_tenant', <string>tenant) OR
                               fn::has_permission(<string>$auth.id, 'role.assign_customers', <string>tenant)
        FOR delete WHERE fn::has_permission(<string>$auth.id, 'role.assign_all', NONE);
DEFINE FIELD user ON TABLE user_role TYPE record<user>;
DEFINE FIELD role ON TABLE user_role TYPE record<role>;
DEFINE FIELD tenant ON TABLE user_role TYPE record<tenant>;
DEFINE FIELD granted_by ON TABLE user_role TYPE record<user>;
DEFINE FIELD granted_at ON TABLE user_role TYPE datetime DEFAULT time::now();
DEFINE FIELD expires_at ON TABLE user_role TYPE option<datetime>;
DEFINE FIELD is_active ON TABLE user_role TYPE bool DEFAULT true;

-- MSP-Customer relationship tracking
DEFINE TABLE msp_customer_relationship SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE fn::has_permission(<string>$auth.id, 'msp.view_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'msp.view_own', <string>msp_tenant)
        FOR create, update, delete WHERE fn::has_permission(<string>$auth.id, 'msp.manage_relationships', <string>msp_tenant) OR
                                        fn::has_permission(<string>$auth.id, 'system.manage', NONE);
DEFINE FIELD msp_tenant ON TABLE msp_customer_relationship TYPE record<tenant>;
DEFINE FIELD customer_tenant ON TABLE msp_customer_relationship TYPE record<tenant>;
DEFINE FIELD relationship_type ON TABLE msp_customer_relationship TYPE string ASSERT $value IN ['managed', 'partner', 'reseller'] DEFAULT 'managed';
DEFINE FIELD billing_arrangement ON TABLE msp_customer_relationship TYPE string ASSERT $value IN ['msp_pays', 'customer_pays', 'split'] DEFAULT 'msp_pays';
DEFINE FIELD commission_rate ON TABLE msp_customer_relationship TYPE option<number>;
DEFINE FIELD contract_start ON TABLE msp_customer_relationship TYPE datetime DEFAULT time::now();
DEFINE FIELD contract_end ON TABLE msp_customer_relationship TYPE option<datetime>;
DEFINE FIELD status ON TABLE msp_customer_relationship TYPE string ASSERT $value IN ['active', 'suspended', 'terminated'] DEFAULT 'active';
DEFINE FIELD created_at ON TABLE msp_customer_relationship TYPE datetime DEFAULT time::now();

-- Enhanced Billing table with MSP considerations
DEFINE TABLE billing SCHEMAFULL
    PERMISSIONS 
        FOR select WHERE fn::has_permission(<string>$auth.id, 'billing.view_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'billing.view_own', <string>tenant) OR
                        fn::has_permission(<string>$auth.id, 'billing.view_customers', <string>tenant)
        FOR create WHERE fn::has_permission(<string>$auth.id, 'billing.create_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'billing.create_customers', <string>tenant)
        FOR update WHERE fn::has_permission(<string>$auth.id, 'billing.update_all', NONE) OR
                        fn::has_permission(<string>$auth.id, 'billing.update_own', <string>tenant) OR
                        fn::has_permission(<string>$auth.id, 'billing.update_customers', <string>tenant)
        FOR delete WHERE fn::has_permission(<string>$auth.id, 'billing.delete_all', NONE);
DEFINE FIELD tenant ON TABLE billing TYPE record<tenant>;
DEFINE FIELD responsible_party ON TABLE billing TYPE record<tenant>; -- Who actually pays
DEFINE FIELD billing_period_start ON TABLE billing TYPE datetime;
DEFINE FIELD billing_period_end ON TABLE billing TYPE datetime;
DEFINE FIELD amount ON TABLE billing TYPE number ASSERT $value >= 0;
DEFINE FIELD currency ON TABLE billing TYPE string DEFAULT 'USD';
DEFINE FIELD status ON TABLE billing TYPE string ASSERT $value IN ['draft', 'pending', 'paid', 'overdue', 'cancelled'] DEFAULT 'draft';
DEFINE FIELD invoice_number ON TABLE billing TYPE string;
DEFINE FIELD msp_commission ON TABLE billing TYPE option<number>;
DEFINE FIELD payment_due_date ON TABLE billing TYPE datetime;
DEFINE FIELD created_at ON TABLE billing TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON TABLE billing TYPE datetime DEFAULT time::now();

-- Indexes for performance
DEFINE INDEX tenant_slug_idx ON TABLE tenant COLUMNS slug UNIQUE;
DEFINE INDEX user_email_idx ON TABLE user COLUMNS email UNIQUE;
DEFINE INDEX user_tenant_idx ON TABLE user_role COLUMNS user, tenant;
DEFINE INDEX msp_customer_idx ON TABLE msp_customer_relationship COLUMNS msp_tenant, customer_tenant UNIQUE;

-- Create hierarchical roles with detailed permissions
INSERT INTO role (id, name, description, level, permissions) VALUES
('role:super_admin', 'Super Admin', 'Full system access across all tenants', 1, [
    'system.manage', 'tenant.create', 'tenant.delete', 'tenant.manage_all', 'tenant.view_all',
    'user.create_all', 'user.update_all', 'user.delete_all', 'user.view_all',
    'msp.create', 'msp.update_all', 'msp.delete_all', 'msp.view_all',
    'billing.create_all', 'billing.update_all', 'billing.delete_all', 'billing.view_all',
    'role.assign_all', 'role.view_all',
    'super_admin.create', 'msp_admin.create', 'tenant_admin.create'
]),
('role:msp_admin', 'MSP Admin', 'Manage MSP tenant and customer tenants', 2, [
    'tenant.view_own', 'tenant.update_own', 'tenant.view_customers', 'tenant.update_customers',
    'user.create_customers', 'user.update_customers', 'user.view_customers', 'user.delete_customers',
    'user.view_own_tenant', 'user.update_own_tenant', 'user.create_own_tenant',
    'msp.view_own', 'msp.update_own', 'msp.manage_relationships',
    'billing.view_customers', 'billing.update_customers', 'billing.create_customers',
    'billing.view_own', 'billing.update_own',
    'role.assign_customers', 'role.assign_own_tenant',
    'msp_admin.create_for_owned_tenants', 'tenant_admin.create_customers', 'user_manager.create_customers'
]),
('role:tenant_admin', 'Tenant Admin', 'Full access within own tenant', 3, [
    'tenant.view_own', 'tenant.update_own', 'tenant.manage_settings',
    'user.create_own_tenant', 'user.update_own_tenant', 'user.view_own_tenant', 'user.delete_own_tenant',
    'billing.view_own', 'billing.update_own',
    'role.assign_own_tenant', 'role.view_own_tenant',
    'tenant_admin.create_own_tenant', 'user_manager.create_own_tenant', 'user.create_own_tenant'
]),
('role:user_manager', 'User Manager', 'Manage users within tenant', 4, [
    'user.create_own_tenant', 'user.update_own_tenant', 'user.view_own_tenant', 'user.delete_basic_own_tenant',
    'role.assign_basic_own_tenant', 'role.view_own_tenant',
    'user.create_own_tenant'
]),
('role:user', 'Standard User', 'Basic user access', 5, [
    'profile.edit', 'profile.view', 'data.view_own', 'settings.view'
]);

-- Create the super admin tenant (root level)
INSERT INTO tenant (id, name, slug, tenant_type, parent_tenant, msp_tenant, contact_email, contact_phone, billing_responsibility) VALUES
('tenant:super_admin', 'System Administration', 'super-admin', 'super_admin', NONE, NONE, 'admin@system.com', '+1-800-SYSTEM', 'self');

-- Create sample MSP tenants
INSERT INTO tenant (id, name, slug, tenant_type, parent_tenant, msp_tenant, contact_email, contact_phone, billing_responsibility) VALUES
('tenant:msp_techcorp', 'TechCorp MSP', 'techcorp-msp', 'msp', tenant:super_admin, NONE, 'admin@techcorp.com', '+1-555-TECH', 'self'),
('tenant:msp_cloudpro', 'CloudPro Services', 'cloudpro-msp', 'msp', tenant:super_admin, NONE, 'billing@cloudpro.com', '+1-555-CLOUD', 'self');

-- Create sample customer tenants under MSPs
INSERT INTO tenant (id, name, slug, tenant_type, parent_tenant, msp_tenant, contact_email, contact_phone, billing_responsibility) VALUES
('tenant:acme_corp', 'Acme Corporation', 'acme-corp', 'customer', tenant:msp_techcorp, tenant:msp_techcorp, 'admin@acme.com', '+1-555-ACME', 'msp'),
('tenant:widgets_inc', 'Widgets Inc', 'widgets-inc', 'customer', tenant:msp_techcorp, tenant:msp_techcorp, 'it@widgets.com', '+1-555-WIDGET', 'self'),
('tenant:startup_xyz', 'Startup XYZ', 'startup-xyz', 'customer', tenant:msp_cloudpro, tenant:msp_cloudpro, 'tech@startupxyz.com', '+1-555-START', 'msp');

-- Create independent customer (direct customer, not through MSP)
INSERT INTO tenant (id, name, slug, tenant_type, parent_tenant, msp_tenant, contact_email, contact_phone, billing_responsibility) VALUES
('tenant:enterprise_direct', 'Enterprise Direct', 'enterprise-direct', 'customer', tenant:super_admin, NONE, 'admin@enterprise.com', '+1-555-ENTER', 'self');

-- Create MSP-Customer relationships
INSERT INTO msp_customer_relationship (msp_tenant, customer_tenant, relationship_type, billing_arrangement, commission_rate) VALUES
(tenant:msp_techcorp, tenant:acme_corp, 'managed', 'msp_pays', 0.15),
(tenant:msp_techcorp, tenant:widgets_inc, 'managed', 'customer_pays', 0.10),
(tenant:msp_cloudpro, tenant:startup_xyz, 'managed', 'msp_pays', 0.20);

-- Create users for different levels
-- Default Super Admin with temporary password that must be changed
INSERT INTO user (id, email, password_hash, password_must_change, first_name, last_name, phone, primary_tenant, accessible_tenants, password_changed_at) VALUES
('user:super_admin', 'super@admin.com', crypto::argon2::generate('TempPassword123!'), true, 'Super', 'Admin', '+1-800-ADMIN', tenant:super_admin, [tenant:super_admin], NONE);

-- Sample MSP and Customer users (for demonstration - these would normally be created via signup)
INSERT INTO user (id, email, password_hash, password_must_change, first_name, last_name, phone, primary_tenant, accessible_tenants, password_changed_at) VALUES
('user:msp_admin_techcorp', 'admin@techcorp.com', crypto::argon2::generate('SamplePassword123!'), false, 'MSP', 'Admin', '+1-555-MSP1', tenant:msp_techcorp, [tenant:msp_techcorp, tenant:acme_corp, tenant:widgets_inc], time::now()),
('user:msp_admin_cloudpro', 'admin@cloudpro.com', crypto::argon2::generate('SamplePassword123!'), false, 'Cloud', 'Admin', '+1-555-MSP2', tenant:msp_cloudpro, [tenant:msp_cloudpro, tenant:startup_xyz], time::now()),
('user:acme_admin', 'admin@acme.com', crypto::argon2::generate('SamplePassword123!'), false, 'Acme', 'Admin', '+1-555-ACME1', tenant:acme_corp, [tenant:acme_corp], time::now()),
('user:widgets_admin', 'admin@widgets.com', crypto::argon2::generate('SamplePassword123!'), false, 'Widgets', 'Admin', '+1-555-WIDGET1', tenant:widgets_inc, [tenant:widgets_inc], time::now()),
('user:enterprise_admin', 'admin@enterprise.com', crypto::argon2::generate('SamplePassword123!'), false, 'Enterprise', 'Admin', '+1-555-ENTER1', tenant:enterprise_direct, [tenant:enterprise_direct], time::now());

-- Assign roles to users
INSERT INTO user_role (user, role, tenant, granted_by) VALUES
(user:super_admin, role:super_admin, tenant:super_admin, user:super_admin),
(user:msp_admin_techcorp, role:msp_admin, tenant:msp_techcorp, user:super_admin),
(user:msp_admin_cloudpro, role:msp_admin, tenant:msp_cloudpro, user:super_admin),
(user:acme_admin, role:tenant_admin, tenant:acme_corp, user:msp_admin_techcorp),
(user:widgets_admin, role:tenant_admin, tenant:widgets_inc, user:msp_admin_techcorp),
(user:enterprise_admin, role:tenant_admin, tenant:enterprise_direct, user:super_admin);

-- Enhanced tenant signup function with MSP support
DEFINE FUNCTION fn::tenant_signup($name: string, $contact_email: string, $tenant_type: string, $parent_tenant_id: option<string>, $msp_tenant_id: option<string>) {
    -- Generate unique slug
    LET $base_slug = string::lowercase(string::replace($name, ' ', '-'));
    LET $base_slug = string::replace($base_slug, '[^a-z0-9-]', '');
    
    -- Check if base slug exists and generate unique one
    LET $existing = SELECT * FROM tenant WHERE slug = $base_slug;
    LET $unique_slug = IF count($existing) > 0 THEN 
        $base_slug + '-' + string::lowercase(rand::uuid()) 
    ELSE 
        $base_slug 
    END;
    
    -- Determine billing responsibility based on MSP relationship
    LET $billing_resp = IF $msp_tenant_id != NONE THEN 'msp' ELSE 'self' END;
    
    -- Create tenant
    LET $tenant = CREATE tenant SET 
        name = $name,
        slug = $unique_slug,
        tenant_type = $tenant_type,
        parent_tenant = IF $parent_tenant_id != NONE THEN type::thing('tenant', $parent_tenant_id) ELSE NONE END,
        msp_tenant = IF $msp_tenant_id != NONE THEN type::thing('tenant', $msp_tenant_id) ELSE NONE END,
        contact_email = $contact_email,
        billing_responsibility = $billing_resp;
    
    -- Create MSP relationship if applicable
    IF $msp_tenant_id != NONE {
        CREATE msp_customer_relationship SET
            msp_tenant = type::thing('tenant', $msp_tenant_id),
            customer_tenant = $tenant.id,
            relationship_type = 'managed',
            billing_arrangement = 'msp_pays';
    };
    
    RETURN $tenant;
};

-- Function to get user's accessible tenants based on role hierarchy
DEFINE FUNCTION fn::get_user_accessible_tenants($user_id: string) {
    LET $user = SELECT * FROM type::thing('user', $user_id);
    LET $user_roles = SELECT role.*, tenant.* FROM user_role WHERE user = type::thing('user', $user_id) AND is_active = true;
    
    LET $accessible = [];
    
    FOR $ur IN $user_roles {
        -- Super admin can access all tenants
        IF $ur.role.name = 'Super Admin' {
            LET $all_tenants = SELECT * FROM tenant;
            LET $accessible = array::union($accessible, $all_tenants);
        }
        -- MSP admin can access their tenant and customer tenants
        ELSE IF $ur.role.name = 'MSP Admin' {
            LET $msp_customers = SELECT customer_tenant.* FROM msp_customer_relationship WHERE msp_tenant = $ur.tenant.id;
            LET $accessible = array::union($accessible, [$ur.tenant]);
            LET $accessible = array::union($accessible, $msp_customers);
        }
        -- Regular tenant admin can only access their own tenant
        ELSE {
            LET $accessible = array::union($accessible, [$ur.tenant]);
        }
    };
    
    RETURN $accessible;
};

-- Function to check if user can manage a specific tenant
DEFINE FUNCTION fn::can_user_manage_tenant($user_id: string, $tenant_id: string) {
    LET $user_roles = SELECT role.*, tenant.* FROM user_role WHERE user = type::thing('user', $user_id) AND is_active = true;
    
    FOR $ur IN $user_roles {
        -- Super admin can manage all tenants
        IF $ur.role.name = 'Super Admin' {
            RETURN true;
        }
        -- MSP admin can manage their customers
        ELSE IF $ur.role.name = 'MSP Admin' {
            LET $is_customer = SELECT * FROM msp_customer_relationship 
                WHERE msp_tenant = $ur.tenant.id AND customer_tenant = type::thing('tenant', $tenant_id);
            IF $is_customer OR $ur.tenant.id = type::thing('tenant', $tenant_id) {
                RETURN true;
            }
        }
        -- Tenant admin can only manage their own tenant
        ELSE IF $ur.tenant.id = type::thing('tenant', $tenant_id) {
            RETURN true;
        }
    };
    
    RETURN false;
};

-- Function to check if user is a super admin
DEFINE FUNCTION fn::is_super_admin($user_id: string) {
    LET $user_roles = SELECT role.name FROM user_role WHERE user = type::thing('user', $user_id) AND is_active = true;
    
    FOR $role IN $user_roles {
        IF $role.name = 'Super Admin' {
            RETURN true;
        }
    };
    
    RETURN false;
};

-- Function to create a super admin user (only callable by existing super admins)
DEFINE FUNCTION fn::create_super_admin($creator_user_id: string, $email: string, $password: string, $first_name: string, $last_name: string, $phone: option<string>) {
    -- Check if creator is a super admin
    LET $is_creator_super_admin = fn::is_super_admin($creator_user_id);
    
    IF !$is_creator_super_admin {
        THROW 'Only Super Admins can create other Super Admins';
    };
    
    -- Check if email already exists
    LET $existing_user = SELECT * FROM user WHERE email = $email;
    IF count($existing_user) > 0 {
        THROW 'User with this email already exists';
    };
    
    -- Create the user
    LET $user = CREATE user SET 
        email = $email,
        password_hash = crypto::argon2::generate($password),
        password_must_change = true,
        first_name = $first_name,
        last_name = $last_name,
        phone = $phone,
        primary_tenant = tenant:super_admin,
        accessible_tenants = [tenant:super_admin],
        is_active = true;
    
    -- Assign super admin role
    CREATE user_role SET
        user = $user.id,
        role = role:super_admin,
        tenant = tenant:super_admin,
        granted_by = type::thing('user', $creator_user_id),
        is_active = true;
    
    RETURN $user;
};

-- Function for secure MSP/Customer signup (prevents super admin creation)
DEFINE FUNCTION fn::secure_signup($email: string, $password: string, $first_name: string, $last_name: string, $phone: option<string>, $tenant_name: string, $tenant_type: string, $contact_email: string, $contact_phone: option<string>, $parent_tenant_id: option<string>, $msp_tenant_id: option<string>) {
    -- Prevent super admin creation through signup
    IF $tenant_type = 'super_admin' {
        THROW 'Cannot create Super Admin tenants through signup';
    };
    
    -- Check if email already exists
    LET $existing_user = SELECT * FROM user WHERE email = $email;
    IF count($existing_user) > 0 {
        THROW 'User with this email already exists';
    };
    
    -- Create tenant first
    LET $tenant = fn::tenant_signup($tenant_name, $contact_email, $tenant_type, $parent_tenant_id, $msp_tenant_id);
    
    -- Create user
    LET $user = CREATE user SET 
        email = $email,
        password_hash = crypto::argon2::generate($password),
        password_must_change = false,
        first_name = $first_name,
        last_name = $last_name,
        phone = $phone,
        primary_tenant = $tenant.id,
        accessible_tenants = [$tenant.id],
        is_active = true,
        password_changed_at = time::now();
    
    -- Assign appropriate role based on tenant type
    LET $role_id = IF $tenant_type = 'msp' THEN role:msp_admin ELSE role:tenant_admin END;
    
    CREATE user_role SET
        user = $user.id,
        role = $role_id,
        tenant = $tenant.id,
        granted_by = user:super_admin,
        is_active = true;
    
    RETURN {
        user: $user,
        tenant: $tenant
    };
};

-- Function to verify password
DEFINE FUNCTION fn::verify_password($user_id: string, $password: string) {
    LET $user = SELECT password_hash FROM user WHERE id = type::thing('user', $user_id);
    IF count($user) = 0 {
        RETURN false;
    };
    
    RETURN crypto::argon2::compare($password, $user[0].password_hash);
};

-- Function to change password
DEFINE FUNCTION fn::change_password($user_id: string, $old_password: string, $new_password: string) {
    LET $user = SELECT * FROM user WHERE id = type::thing('user', $user_id);
    IF count($user) = 0 {
        THROW 'User not found';
    };
    
    -- Verify old password (skip for forced password change)
    IF !$user[0].password_must_change {
        LET $password_valid = crypto::argon2::compare($old_password, $user[0].password_hash);
        IF !$password_valid {
            THROW 'Invalid current password';
        };
    };
    
    -- Update password
    UPDATE type::thing('user', $user_id) SET 
        password_hash = crypto::argon2::generate($new_password),
        password_must_change = false,
        password_changed_at = time::now(),
        updated_at = time::now();
    
    RETURN 'Password updated successfully';
};

-- Function to check if user has specific permission
DEFINE FUNCTION fn::has_permission($user_id: string, $permission: string, $tenant_id: option<string>) {
    LET $user_roles = SELECT role.permissions, role.name, tenant.id as tenant_id FROM user_role 
        WHERE user = type::thing('user', $user_id) AND is_active = true;
    
    FOR $ur IN $user_roles {
        -- Check if user has the exact permission
        IF $permission IN $ur.permissions {
            -- For tenant-specific permissions, check if it applies to the right tenant
            IF $tenant_id != NONE {
                -- Super admin permissions apply everywhere
                IF $ur.name = 'Super Admin' {
                    RETURN true;
                }
                -- MSP admin permissions apply to owned and customer tenants
                ELSE IF $ur.name = 'MSP Admin' AND (
                    $ur.tenant_id = type::thing('tenant', $tenant_id) OR
                    type::thing('tenant', $tenant_id) IN (SELECT customer_tenant FROM msp_customer_relationship WHERE msp_tenant = $ur.tenant_id)
                ) {
                    RETURN true;
                }
                -- Other roles only apply to their own tenant
                ELSE IF $ur.tenant_id = type::thing('tenant', $tenant_id) {
                    RETURN true;
                }
            } ELSE {
                -- Global permission
                RETURN true;
            }
        }
    };
    
    RETURN false;
};

-- Function to create user with permission checks
DEFINE FUNCTION fn::create_user_with_permissions($creator_user_id: string, $email: string, $password: string, $first_name: string, $last_name: string, $phone: option<string>, $tenant_id: string, $role_name: string) {
    -- Check if creator has permission to create users in this tenant
    LET $can_create = fn::has_permission($creator_user_id, 'user.create_own_tenant', $tenant_id) OR
                      fn::has_permission($creator_user_id, 'user.create_customers', $tenant_id) OR
                      fn::has_permission($creator_user_id, 'user.create_all', NONE);
    
    IF !$can_create {
        THROW 'Insufficient permissions to create users in this tenant';
    };
    
    -- Additional checks for role assignment
    LET $creator_roles = SELECT role.name FROM user_role WHERE user = type::thing('user', $creator_user_id) AND is_active = true;
    LET $is_super_admin = 'Super Admin' IN $creator_roles.name;
    LET $is_msp_admin = 'MSP Admin' IN $creator_roles.name;
    LET $is_tenant_admin = 'Tenant Admin' IN $creator_roles.name;
    
    -- Role creation restrictions based on your requirements
    IF $role_name = 'Super Admin' AND !$is_super_admin {
        THROW 'Only Super Admins can create Super Admins';
    };
    
    IF $role_name = 'MSP Admin' AND !($is_super_admin OR $is_msp_admin) {
        THROW 'Only Super Admins or MSP Admins can create MSP Admins';
    };
    
    -- Check if email already exists
    LET $existing_user = SELECT * FROM user WHERE email = $email;
    IF count($existing_user) > 0 {
        THROW 'User with this email already exists';
    };
    
    -- Create the user
    LET $user = CREATE user SET 
        email = $email,
        password_hash = crypto::argon2::generate($password),
        password_must_change = true,
        first_name = $first_name,
        last_name = $last_name,
        phone = $phone,
        primary_tenant = type::thing('tenant', $tenant_id),
        accessible_tenants = [type::thing('tenant', $tenant_id)],
        is_active = true;
    
    -- Assign role
    LET $role = SELECT * FROM role WHERE name = $role_name;
    IF count($role) = 0 {
        THROW 'Invalid role name';
    };
    
    CREATE user_role SET
        user = $user.id,
        role = $role[0].id,
        tenant = type::thing('tenant', $tenant_id),
        granted_by = type::thing('user', $creator_user_id),
        is_active = true;
    
    RETURN $user;
};

-- Function to update user with permission checks
DEFINE FUNCTION fn::update_user_with_permissions($updater_user_id: string, $target_user_id: string, $updates: object) {
    LET $target_user = SELECT * FROM user WHERE id = type::thing('user', $target_user_id);
    IF count($target_user) = 0 {
        THROW 'User not found';
    };
    
    LET $target_tenant_id = string::split(<string>$target_user[0].primary_tenant, ':')[1];
    
    -- Check if updater has permission to update users in target tenant
    LET $can_update = fn::has_permission($updater_user_id, 'user.update_own_tenant', $target_tenant_id) OR
                      fn::has_permission($updater_user_id, 'user.update_customers', $target_tenant_id) OR
                      fn::has_permission($updater_user_id, 'user.update_all', NONE);
    
    IF !$can_update {
        THROW 'Insufficient permissions to update this user';
    };
    
    -- Apply updates
    UPDATE type::thing('user', $target_user_id) MERGE $updates;
    UPDATE type::thing('user', $target_user_id) SET updated_at = time::now();
    
    RETURN 'User updated successfully';
};

-- Function to update tenant with permission checks
DEFINE FUNCTION fn::update_tenant_with_permissions($updater_user_id: string, $tenant_id: string, $updates: object) {
    -- Check if updater has permission to update this tenant
    LET $can_update = fn::has_permission($updater_user_id, 'tenant.update_own', $tenant_id) OR
                      fn::has_permission($updater_user_id, 'tenant.update_customers', $tenant_id) OR
                      fn::has_permission($updater_user_id, 'tenant.manage_all', NONE);
    
    IF !$can_update {
        THROW 'Insufficient permissions to update this tenant';
    };
    
    -- Apply updates
    UPDATE type::thing('tenant', $tenant_id) MERGE $updates;
    UPDATE type::thing('tenant', $tenant_id) SET updated_at = time::now();
    
    RETURN 'Tenant updated successfully';
};

-- Function to assign role with permission checks
DEFINE FUNCTION fn::assign_role_with_permissions($assigner_user_id: string, $target_user_id: string, $role_name: string, $tenant_id: string) {
    LET $target_user = SELECT * FROM user WHERE id = type::thing('user', $target_user_id);
    IF count($target_user) = 0 {
        THROW 'User not found';
    };
    
    -- Check if assigner has permission to assign roles in this tenant
    LET $can_assign = fn::has_permission($assigner_user_id, 'role.assign_own_tenant', $tenant_id) OR
                      fn::has_permission($assigner_user_id, 'role.assign_customers', $tenant_id) OR
                      fn::has_permission($assigner_user_id, 'role.assign_all', NONE);
    
    IF !$can_assign {
        THROW 'Insufficient permissions to assign roles in this tenant';
    };
    
    -- Role assignment restrictions
    LET $assigner_roles = SELECT role.name FROM user_role WHERE user = type::thing('user', $assigner_user_id) AND is_active = true;
    LET $is_super_admin = 'Super Admin' IN $assigner_roles.name;
    LET $is_msp_admin = 'MSP Admin' IN $assigner_roles.name;
    
    IF $role_name = 'Super Admin' AND !$is_super_admin {
        THROW 'Only Super Admins can assign Super Admin role';
    };
    
    IF $role_name = 'MSP Admin' AND !($is_super_admin OR $is_msp_admin) {
        THROW 'Only Super Admins or MSP Admins can assign MSP Admin role';
    };
    
    -- Deactivate existing roles for this user in this tenant
    UPDATE user_role SET is_active = false 
    WHERE user = type::thing('user', $target_user_id) AND tenant = type::thing('tenant', $tenant_id);
    
    -- Assign new role
    LET $role = SELECT * FROM role WHERE name = $role_name;
    IF count($role) = 0 {
        THROW 'Invalid role name';
    };
    
    CREATE user_role SET
        user = type::thing('user', $target_user_id),
        role = $role[0].id,
        tenant = type::thing('tenant', $tenant_id),
        granted_by = type::thing('user', $assigner_user_id),
        is_active = true;
    
    RETURN 'Role assigned successfully';
};

-- Sample queries to demonstrate the hierarchy:

-- Get all MSP customers for a specific MSP
-- SELECT customer_tenant.* FROM msp_customer_relationship WHERE msp_tenant = tenant:msp_techcorp;

-- Get billing summary for an MSP (including customer billing)
-- SELECT billing.*, tenant.name as tenant_name FROM billing 
-- WHERE responsible_party = tenant:msp_techcorp 
-- OR tenant IN (SELECT customer_tenant FROM msp_customer_relationship WHERE msp_tenant = tenant:msp_techcorp);

-- Get user's role within a specific tenant
-- SELECT role.name FROM user_role WHERE user = user:msp_admin_techcorp AND tenant = tenant:acme_corp;