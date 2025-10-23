import { z } from 'zod'

// Define the request body schema with strong typing and validation
const signupSchema = z.object({
  email: z.string().min(1, 'Email is required').email('Invalid email format'),
  first_name: z.string().min(1, 'First Name is required').max(100, 'First Name is too long').trim(),
  last_name: z.string().min(1, 'Last Name is required').max(100, 'Last Name is too long').trim(),
  password: z
    .string()
    .min(8, 'Password must be at least 8 characters long')
    .max(128, 'Password is too long'),
  company_name: z
    .string()
    .min(2, 'Company name must be at least 2 characters long')
    .max(100, 'Company name is too long')
    .trim(),
  isMsp: z.boolean()
})

// Define the response types
interface MembershipData {
  id: string
  role: string
  status: string
  joined_at: string
  user_settings: Record<string, unknown>
  tenant_metadata: Record<string, unknown>
}

interface SignupSuccessResponse {
  success: true
  message: string
  data: {
    user: {
      id: string
      email: string
      name: string
    }
    tenant: {
      id: string
      name: string
      slug: string
    }
    membership: MembershipData
  }
}

interface SignupErrorResponse {
  success: false
  message: string
  statusCode: number
}

type SignupResponse = SignupSuccessResponse | SignupErrorResponse

export default defineEventHandler(async (event): Promise<SignupResponse> => {
  try {
    // Parse and validate the request body
    const body = await readBody(event)

    // Validate the input using Zod schema
    const validatedData = signupSchema.parse(body)

    const tenantType = validatedData.isMsp ? 'msp' : 'customer'

    // Get SurrealDB query function
    const { sql } = useSurrealDB(event)

    // Create user and tenant directly instead of using the problematic function
    // First check if user already exists
    const existingUser = await sql(
      'SELECT * FROM user WHERE email = $email',
      { email: validatedData.email },
      { database: 'default' }
    )

    if (
      existingUser?.[0]?.result &&
      Array.isArray(existingUser[0].result) &&
      existingUser[0].result.length > 0
    ) {
      throw createError({
        statusCode: 409,
        statusMessage: 'An account with this email already exists'
      })
    }

    // Create tenant first
    const tenantSlug = validatedData.company_name
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '')
    const tenant = await sql(
      `CREATE tenant SET 
        name = $name,
        slug = $slug,
        tenant_type = $tenant_type,
        contact_email = $contact_email,
        billing_responsibility = 'self',
        status = 'active'`,
      {
        name: validatedData.company_name,
        slug: tenantSlug + '-' + Date.now(),
        tenant_type: tenantType,
        contact_email: validatedData.email
      },
      { database: 'default' }
    )

    if (!tenant?.[0]?.result) {
      console.error('Tenant creation failed:', JSON.stringify(tenant, null, 2))
      throw createError({
        statusCode: 500,
        statusMessage: 'Failed to create tenant'
      })
    }

    const createdTenant = Array.isArray(tenant[0].result) ? tenant[0].result[0] : tenant[0].result

    // Create user
    const user = await sql(
      `CREATE user SET 
        email = $email,
        password_hash = crypto::argon2::generate($password),
        password_must_change = false,
        first_name = $first_name,
        last_name = $last_name,
        primary_tenant = $tenant_id,
        accessible_tenants = [$tenant_id],
        is_active = true,
        password_changed_at = time::now()`,
      {
        email: validatedData.email,
        password: validatedData.password,
        first_name: validatedData.first_name,
        last_name: validatedData.last_name,
        tenant_id: createdTenant.id
      },
      { database: 'default' }
    )

    if (!user?.[0]?.result) {
      console.error('User creation failed:', JSON.stringify(user, null, 2))
      throw createError({
        statusCode: 500,
        statusMessage: 'Failed to create user'
      })
    }

    const createdUser = Array.isArray(user[0].result) ? user[0].result[0] : user[0].result

    // Assign role
    const roleId = tenantType === 'msp' ? 'role:msp_admin' : 'role:tenant_admin'
    await sql(
      `CREATE user_role SET
        user = $user_id,
        role = $role_id,
        tenant = $tenant_id,
        granted_by = user:super_admin,
        is_active = true`,
      {
        user_id: createdUser.id,
        role_id: roleId,
        tenant_id: createdTenant.id
      },
      { database: 'default' }
    )

    // Return successful response with created user and tenant
    return {
      success: true,
      message: 'Account created successfully',
      data: {
        user: {
          id: createdUser.id,
          email: createdUser.email,
          name: `${createdUser.first_name} ${createdUser.last_name}`.trim()
        },
        tenant: {
          id: createdTenant.id,
          name: createdTenant.name,
          slug: createdTenant.slug
        },
        membership: {
          id: `${createdUser.id}-${createdTenant.id}`,
          role: tenantType === 'msp' ? 'MSP Admin' : 'Tenant Admin',
          status: 'active',
          joined_at: new Date().toISOString(),
          user_settings: {},
          tenant_metadata: createdTenant.settings || {}
        }
      }
    }
  } catch (error: unknown) {
    console.error('Signup API error:', error)
    console.error('Error type:', typeof error)
    console.error('Error details:', JSON.stringify(error, null, 2))

    // Handle Zod validation errors
    if (error instanceof z.ZodError) {
      const validationErrors = (error as z.ZodError).issues
        .map((err: any) => `${err.path.join('.')}: ${err.message}`)
        .join(', ')

      throw createError({
        statusCode: 400,
        statusMessage: `Validation error: ${validationErrors}`
      })
    }

    // Handle SurrealDB/business logic errors
    if (error && typeof error === 'object' && 'message' in error) {
      const message = (error as { message: string }).message

      // Map specific database errors to user-friendly messages
      if (message.includes('email already exists')) {
        throw createError({
          statusCode: 409,
          statusMessage: 'An account with this email already exists'
        })
      }

      if (message.includes('slug already exists')) {
        throw createError({
          statusCode: 409,
          statusMessage: 'A company with this name already exists. Please try a different name.'
        })
      }

      if (message.includes('Invalid email format')) {
        throw createError({
          statusCode: 400,
          statusMessage: 'Please enter a valid email address'
        })
      }

      if (message.includes('Password must be')) {
        throw createError({
          statusCode: 400,
          statusMessage: 'Password must be at least 8 characters long'
        })
      }

      if (message.includes('Not enough permissions')) {
        throw createError({
          statusCode: 500,
          statusMessage: 'Database permission error. Please contact support.'
        })
      }
    }

    // Generic error fallback
    throw createError({
      statusCode: 500,
      statusMessage: 'An unexpected error occurred. Please try again later.'
    })
  }
})
