# Core Functions Reference

This document provides detailed information about all the functions available in the MSP database schema.

## 📋 Function Categories

- [User Management](#user-management)
- [Tenant Operations](#tenant-operations)
- [Permission System](#permission-system)
- [Authentication](#authentication)
- [Role Management](#role-management)

---

## User Management

### `fn::create_user_with_permissions()`

Creates a new user with comprehensive permission checking and role validation.

**Signature:**

```sql
fn::create_user_with_permissions(
    $creator_user_id: string,
    $email: string,
    $password: string,
    $first_name: string,
    $last_name: string,
    $phone: option<string>,
    $tenant_id: string,
    $role_name: string
) -> user
```

**Parameters:**

- `creator_user_id`: ID of the user creating the new user
- `email`: Email address (must be unique)
- `password`: Plain text password (will be hashed with Argon2)
- `first_name`: User's first name
- `last_name`: User's last name
- `phone`: Optional phone number
- `tenant_id`: Target tenant for the new user
- `role_name`: Role to assign to the user

**Permission Checks:**

- Creator must have `user.create_own_tenant`, `user.create_customers`, or `user.create_all`
- Role assignment follows hierarchy rules (only Super Admins can create Super Admins)

**Example:**

```sql
SELECT * FROM fn::create_user_with_permissions(
    'super_admin',
    'manager@acme.com',
    'SecurePassword123!',
    'John',
    'Manager',
    '+1-555-0123',
    'acme_corp',
    'User Manager'
);
```

### `fn::update_user_with_permissions()`

Updates an existing user with permission validation.

**Signature:**

```sql
fn::update_user_with_permissions(
    $updater_user_id: string,
    $target_user_id: string,
    $updates: object
) -> string
```

**Parameters:**

- `updater_user_id`: ID of user performing the update
- `target_user_id`: ID of user being updated
- `updates`: Object containing fields to update

**Permission Checks:**

- Updater must have appropriate permissions for target user's tenant
- Users can always update themselves

**Example:**

```sql
SELECT * FROM fn::update_user_with_permissions(
    'admin_user_id',
    'target_user_id',
    {
        first_name: 'Updated',
        phone: '+1-555-9999'
    }
);
```

---

## Tenant Operations

### `fn::tenant_signup()`

Creates a new tenant with automatic slug generation and MSP relationship setup.

**Signature:**

```sql
fn::tenant_signup(
    $name: string,
    $contact_email: string,
    $tenant_type: string,
    $parent_tenant_id: option<string>,
    $msp_tenant_id: option<string>
) -> tenant
```

**Parameters:**

- `name`: Display name for the tenant
- `contact_email`: Primary contact email
- `tenant_type`: Type (`'super_admin'`, `'msp'`, `'customer'`)
- `parent_tenant_id`: Optional parent tenant ID
- `msp_tenant_id`: Optional MSP tenant ID for billing

**Features:**

- Automatic slug generation with collision handling
- MSP relationship creation
- Billing responsibility determination

**Example:**

```sql
SELECT * FROM fn::tenant_signup(
    'Acme Corporation',
    'admin@acme.com',
    'customer',
    'msp_techcorp',
    'msp_techcorp'
);
```

### `fn::secure_signup()`

Complete tenant and admin user creation in a single transaction.

**Signature:**

```sql
fn::secure_signup(
    $email: string,
    $password: string,
    $first_name: string,
    $last_name: string,
    $phone: option<string>,
    $tenant_name: string,
    $tenant_type: string,
    $contact_email: string,
    $contact_phone: option<string>,
    $parent_tenant_id: option<string>,
    $msp_tenant_id: option<string>
) -> { user, tenant }
```

**Security Features:**

- Prevents super admin creation through signup
- Email uniqueness validation
- Automatic role assignment based on tenant type

**Example:**

```sql
SELECT * FROM fn::secure_signup(
    'admin@newcustomer.com',
    'TempPassword123!',
    'Admin',
    'User',
    '+1-555-0155',
    'New Customer Inc',
    'customer',
    'billing@newcustomer.com',
    '+1-555-0156',
    'msp_techcorp',
    'msp_techcorp'
);
```

### `fn::update_tenant_with_permissions()`

Updates tenant information with permission validation.

**Signature:**

```sql
fn::update_tenant_with_permissions(
    $updater_user_id: string,
    $tenant_id: string,
    $updates: object
) -> string
```

---

## Permission System

### `fn::has_permission()`

Core permission checking function that validates user permissions with tenant context.

**Signature:**

```sql
fn::has_permission(
    $user_id: string,
    $permission: string,
    $tenant_id: option<string>
) -> bool
```

**Parameters:**

- `user_id`: User to check permissions for
- `permission`: Permission string (e.g., `'user.create_own_tenant'`)
- `tenant_id`: Optional tenant context for scoped permissions

**Permission Logic:**

- Super Admin permissions apply globally
- MSP Admin permissions apply to owned and customer tenants
- Other roles only apply within their own tenant

**Example:**

```sql
-- Check if user can create users in a specific tenant
SELECT fn::has_permission('user123', 'user.create_own_tenant', 'acme_corp');

-- Check global permission
SELECT fn::has_permission('super_admin', 'system.manage', NONE);
```

### `fn::get_user_accessible_tenants()`

Returns all tenants a user can access based on their roles.

**Signature:**

```sql
fn::get_user_accessible_tenants($user_id: string) -> array<tenant>
```

**Access Rules:**

- **Super Admin**: All tenants
- **MSP Admin**: Their MSP + all customer tenants
- **Others**: Only their primary tenant

**Example:**

```sql
SELECT * FROM fn::get_user_accessible_tenants('msp_admin_techcorp');
```

### `fn::can_user_manage_tenant()`

Checks if a user can perform management actions on a specific tenant.

**Signature:**

```sql
fn::can_user_manage_tenant($user_id: string, $tenant_id: string) -> bool
```

---

## Authentication

### `fn::verify_password()`

Securely verifies a user's password using Argon2.

**Signature:**

```sql
fn::verify_password($user_id: string, $password: string) -> bool
```

**Example:**

```sql
SELECT fn::verify_password('user123', 'UserPassword123!');
```

### `fn::change_password()`

Changes a user's password with proper validation and security.

**Signature:**

```sql
fn::change_password(
    $user_id: string,
    $old_password: string,
    $new_password: string
) -> string
```

**Security Features:**

- Verifies old password (unless forced change)
- Updates password hash with Argon2
- Records password change timestamp
- Clears forced password change flag

**Example:**

```sql
SELECT * FROM fn::change_password('user123', 'OldPass123!', 'NewPass456!');
```

---

## Role Management

### `fn::assign_role_with_permissions()`

Assigns a role to a user with comprehensive permission and hierarchy validation.

**Signature:**

```sql
fn::assign_role_with_permissions(
    $assigner_user_id: string,
    $target_user_id: string,
    $role_name: string,
    $tenant_id: string
) -> string
```

**Validation Rules:**

- Assigner must have role assignment permissions
- Role hierarchy restrictions enforced
- Deactivates existing roles in the target tenant

**Example:**

```sql
SELECT * FROM fn::assign_role_with_permissions(
    'msp_admin',
    'target_user',
    'Tenant Admin',
    'customer_tenant'
);
```

### `fn::is_super_admin()`

Checks if a user has Super Admin privileges.

**Signature:**

```sql
fn::is_super_admin($user_id: string) -> bool
```

### `fn::create_super_admin()`

Creates a new Super Admin user (only callable by existing Super Admins).

**Signature:**

```sql
fn::create_super_admin(
    $creator_user_id: string,
    $email: string,
    $password: string,
    $first_name: string,
    $last_name: string,
    $phone: option<string>
) -> user
```

**Security:**

- Only existing Super Admins can create new ones
- Email uniqueness validation
- Forces password change on first login

---

## Error Handling

All functions include comprehensive error handling:

- **Permission Errors**: Clear messages about insufficient permissions
- **Validation Errors**: Specific feedback on invalid data
- **Security Errors**: Protection against unauthorized operations
- **Data Integrity**: Prevents duplicate emails and invalid relationships

## Best Practices

1. **Always use permission-checking functions** instead of direct table access
2. **Validate user input** before passing to functions
3. **Handle errors gracefully** in your application
4. **Use transactions** for multi-step operations
5. **Log function calls** for audit trails
