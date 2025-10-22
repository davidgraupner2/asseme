# API Examples and Usage Patterns

This guide provides practical examples for common operations using the MSP database schema.

## 🚀 Getting Started Examples

### Initial Setup

After deploying the schema, you'll have a default Super Admin account:

```sql
-- Default Super Admin credentials
Email: super@admin.com
Password: TempPassword123!
Status: password_must_change = true
```

### First Login and Password Change

```sql
-- Verify the default admin credentials
SELECT fn::verify_password('super_admin', 'TempPassword123!');

-- Change the default password
SELECT * FROM fn::change_password(
    'super_admin',
    'TempPassword123!',
    'MySecurePassword456!'
);
```

## 🏢 Organization Setup

### Creating Your First MSP

```sql
-- Create a new MSP with admin user
SELECT * FROM fn::secure_signup(
    'admin@techcorp-msp.com',
    'SecurePassword123!',
    'Tech',
    'Admin',
    '+1-555-TECH',
    'TechCorp MSP',
    'msp',
    'billing@techcorp-msp.com',
    '+1-555-TECH-BILL',
    'super_admin',  -- Parent tenant
    NONE           -- No MSP (this IS the MSP)
);
```

### Adding a Customer Under the MSP

```sql
-- Create customer tenant with admin
SELECT * FROM fn::secure_signup(
    'admin@acmecorp.com',
    'CustomerPassword123!',
    'Jane',
    'Smith',
    '+1-555-ACME',
    'Acme Corporation',
    'customer',
    'billing@acmecorp.com',
    '+1-555-ACME-BILL',
    'msp_techcorp',  -- Parent MSP
    'msp_techcorp'   -- MSP handles billing
);
```

### Creating a Direct Customer (No MSP)

```sql
-- Direct customer under Super Admin
SELECT * FROM fn::secure_signup(
    'admin@enterprise.com',
    'EnterprisePassword123!',
    'Enterprise',
    'Admin',
    '+1-555-ENTER',
    'Enterprise Direct',
    'customer',
    'billing@enterprise.com',
    '+1-555-ENTER-BILL',
    'super_admin',  -- Direct under super admin
    NONE           -- No MSP
);
```

## 👥 User Management

### Adding Users to Existing Tenants

```sql
-- Add a User Manager to Acme Corp (by MSP Admin)
SELECT * FROM fn::create_user_with_permissions(
    'msp_admin_techcorp',  -- Creator (MSP Admin)
    'manager@acmecorp.com',
    'ManagerPassword123!',
    'John',
    'Manager',
    '+1-555-ACME-MGR',
    'acme_corp',           -- Target tenant
    'User Manager'         -- Role
);

-- Add a standard user (by Tenant Admin)
SELECT * FROM fn::create_user_with_permissions(
    'acme_admin',          -- Creator (Tenant Admin)
    'user@acmecorp.com',
    'UserPassword123!',
    'Regular',
    'User',
    '+1-555-ACME-USER',
    'acme_corp',
    'Standard User'
);
```

### Updating User Information

```sql
-- Update user details
SELECT * FROM fn::update_user_with_permissions(
    'acme_admin',
    'target_user_id',
    {
        first_name: 'Updated',
        last_name: 'Name',
        phone: '+1-555-NEW-PHONE'
    }
);
```

### Password Management

```sql
-- User changes their own password
SELECT * FROM fn::change_password(
    'user_id',
    'OldPassword123!',
    'NewPassword456!'
);

-- Force password change (admin action)
SELECT * FROM fn::update_user_with_permissions(
    'admin_user_id',
    'target_user_id',
    {
        password_must_change: true
    }
);
```

## 🎭 Role Management

### Assigning Roles

```sql
-- MSP Admin assigns Tenant Admin role to customer user
SELECT * FROM fn::assign_role_with_permissions(
    'msp_admin_techcorp',
    'target_user_id',
    'Tenant Admin',
    'acme_corp'
);

-- Tenant Admin assigns User Manager role
SELECT * FROM fn::assign_role_with_permissions(
    'acme_admin',
    'target_user_id',
    'User Manager',
    'acme_corp'
);
```

### Checking User Roles

```sql
-- Get all roles for a user
SELECT
    role.name as role_name,
    tenant.name as tenant_name,
    granted_at,
    expires_at
FROM user_role
WHERE user = user:target_user AND is_active = true;

-- Check if user is Super Admin
SELECT fn::is_super_admin('user_id');
```

## 🔐 Permission Checking

### Basic Permission Checks

```sql
-- Check if user can create users in a tenant
SELECT fn::has_permission('user_id', 'user.create_own_tenant', 'tenant_id');

-- Check global permissions
SELECT fn::has_permission('super_admin', 'system.manage', NONE);

-- Check MSP permissions
SELECT fn::has_permission('msp_admin', 'msp.view_own', 'msp_tenant_id');
```

### Tenant Access Checks

```sql
-- Get all tenants user can access
SELECT * FROM fn::get_user_accessible_tenants('user_id');

-- Check if user can manage specific tenant
SELECT fn::can_user_manage_tenant('user_id', 'tenant_id');
```

## 🏢 Tenant Operations

### Updating Tenant Information

```sql
-- Update tenant settings
SELECT * FROM fn::update_tenant_with_permissions(
    'admin_user_id',
    'tenant_id',
    {
        name: 'Updated Company Name',
        contact_email: 'new-contact@company.com',
        settings: {
            feature_flags: {
                advanced_reporting: true,
                api_access: true
            }
        }
    }
);
```

### Managing MSP Relationships

```sql
-- View MSP customers
SELECT
    customer_tenant.name as customer_name,
    relationship_type,
    billing_arrangement,
    commission_rate
FROM msp_customer_relationship
WHERE msp_tenant = tenant:msp_techcorp;

-- Update MSP relationship
UPDATE msp_customer_relationship
SET commission_rate = 0.20,
    billing_arrangement = 'customer_pays'
WHERE msp_tenant = tenant:msp_techcorp
  AND customer_tenant = tenant:acme_corp;
```

## 💰 Billing Operations

### Creating Billing Records

```sql
-- Create billing record for a customer
INSERT INTO billing (
    tenant,
    responsible_party,
    billing_period_start,
    billing_period_end,
    amount,
    currency,
    status,
    invoice_number,
    payment_due_date
) VALUES (
    tenant:acme_corp,
    tenant:msp_techcorp,  -- MSP pays
    '2024-01-01T00:00:00Z',
    '2024-01-31T23:59:59Z',
    999.99,
    'USD',
    'pending',
    'INV-2024-001',
    '2024-02-15T00:00:00Z'
);
```

### Billing Queries

```sql
-- Get all billing for an MSP (including customers)
SELECT
    billing.*,
    tenant.name as tenant_name
FROM billing
WHERE responsible_party = tenant:msp_techcorp
   OR tenant IN (
       SELECT customer_tenant
       FROM msp_customer_relationship
       WHERE msp_tenant = tenant:msp_techcorp
   );

-- Monthly billing summary
SELECT
    responsible_party.name as payer,
    SUM(amount) as total_amount,
    COUNT(*) as invoice_count
FROM billing
WHERE billing_period_start >= '2024-01-01T00:00:00Z'
  AND billing_period_end <= '2024-01-31T23:59:59Z'
GROUP BY responsible_party;
```

## 📊 Reporting and Analytics

### User Activity Reports

```sql
-- Active users by tenant
SELECT
    primary_tenant.name as tenant_name,
    COUNT(*) as active_users
FROM user
WHERE is_active = true
GROUP BY primary_tenant;

-- Users with forced password changes
SELECT
    email,
    first_name,
    last_name,
    primary_tenant.name as tenant
FROM user
WHERE password_must_change = true;
```

### Tenant Hierarchy Reports

```sql
-- Complete tenant hierarchy
SELECT
    t.name as tenant_name,
    t.tenant_type,
    pt.name as parent_name,
    mt.name as msp_name
FROM tenant t
LEFT JOIN tenant pt ON t.parent_tenant = pt.id
LEFT JOIN tenant mt ON t.msp_tenant = mt.id
ORDER BY t.tenant_type, t.name;

-- MSP customer counts
SELECT
    msp.name as msp_name,
    COUNT(rel.customer_tenant) as customer_count
FROM tenant msp
LEFT JOIN msp_customer_relationship rel ON msp.id = rel.msp_tenant
WHERE msp.tenant_type = 'msp'
GROUP BY msp.id, msp.name;
```

### Permission Audit

```sql
-- Users with Super Admin access
SELECT
    u.email,
    u.first_name,
    u.last_name,
    ur.granted_at,
    ur.granted_by.email as granted_by_email
FROM user_role ur
JOIN user u ON ur.user = u.id
JOIN role r ON ur.role = r.id
WHERE r.name = 'Super Admin' AND ur.is_active = true;

-- Role distribution
SELECT
    r.name as role_name,
    COUNT(ur.user) as user_count
FROM user_role ur
JOIN role r ON ur.role = r.id
WHERE ur.is_active = true
GROUP BY r.id, r.name
ORDER BY user_count DESC;
```

## 🔧 Advanced Patterns

### Bulk User Creation

```sql
-- Create multiple users in a loop (example pattern)
FOR $user_data IN [
    {
        email: 'user1@acme.com',
        first_name: 'User',
        last_name: 'One'
    },
    {
        email: 'user2@acme.com',
        first_name: 'User',
        last_name: 'Two'
    }
] {
    LET $result = fn::create_user_with_permissions(
        'acme_admin',
        $user_data.email,
        'TempPassword123!',
        $user_data.first_name,
        $user_data.last_name,
        NONE,
        'acme_corp',
        'Standard User'
    );
};
```

### Tenant Migration

```sql
-- Move a user to a different tenant (admin operation)
BEGIN TRANSACTION;

-- Update user's primary tenant
UPDATE user:target_user SET
    primary_tenant = tenant:new_tenant,
    accessible_tenants = [tenant:new_tenant];

-- Deactivate old roles
UPDATE user_role SET is_active = false
WHERE user = user:target_user;

-- Assign new role in new tenant
INSERT INTO user_role (user, role, tenant, granted_by) VALUES
(user:target_user, role:user, tenant:new_tenant, user:admin);

COMMIT TRANSACTION;
```

### Custom Permissions Check

```sql
-- Complex permission logic example
DEFINE FUNCTION fn::can_access_billing($user_id: string, $billing_id: string) {
    LET $billing = SELECT * FROM type::thing('billing', $billing_id);
    LET $tenant_id = string::split(<string>$billing[0].tenant, ':')[1];

    RETURN fn::has_permission($user_id, 'billing.view_all', NONE) OR
           fn::has_permission($user_id, 'billing.view_own', $tenant_id) OR
           fn::has_permission($user_id, 'billing.view_customers', $tenant_id);
};
```

## 🐛 Debugging and Troubleshooting

### Common Debugging Queries

```sql
-- Check user authentication context
SELECT $auth;

-- Verify user exists and is active
SELECT * FROM user WHERE email = 'user@example.com' AND is_active = true;

-- Debug permission function
SELECT fn::has_permission('user_id', 'permission.string', 'tenant_id') as has_permission;

-- Check role assignments
SELECT
    ur.*,
    r.name as role_name,
    r.permissions
FROM user_role ur
JOIN role r ON ur.role = r.id
WHERE ur.user = user:target_user AND ur.is_active = true;
```

### Performance Optimization

```sql
-- Use indexes for common queries
SELECT * FROM user WHERE email = 'user@example.com';  -- Uses user_email_idx

-- Efficient tenant hierarchy queries
SELECT * FROM tenant WHERE parent_tenant = tenant:msp_techcorp;

-- Optimize permission checks with specific tenant context
SELECT * FROM user
WHERE fn::has_permission('msp_admin', 'user.view_customers', <string>primary_tenant);
```

These examples provide a comprehensive foundation for building applications on top of the MSP database schema. Always remember to handle errors appropriately and validate user input before executing operations.
