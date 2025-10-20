import { z } from 'zod'

// Define the request body schema with strong typing and validation
const signupSchema = z.object({
  email: z.string().min(1, 'Email is required').email('Invalid email format'),
  password: z
    .string()
    .min(8, 'Password must be at least 8 characters long')
    .max(128, 'Password is too long'),
  name: z.string().min(1, 'Name is required').max(100, 'Name is too long').trim(),
  company_name: z
    .string()
    .min(2, 'Company name must be at least 2 characters long')
    .max(100, 'Company name is too long')
    .trim()
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

    console.log('Processing signup for:', validatedData.email)

    // Get SurrealDB query function
    const { query } = useSurrealDB(event)

    // Call the tenant signup function with validated data
    const result = await query(
      'RETURN fn::tenant_signup($user_email, $user_password, $user_name, $tenant_name, $tenant_description, $user_metadata, $tenant_settings)',
      {
        user_email: validatedData.email,
        user_password: validatedData.password,
        user_name: validatedData.name,
        tenant_name: validatedData.company_name,
        tenant_description: `${validatedData.company_name} organization`,
        user_metadata: {
          signup_date: new Date().toISOString(),
          source: 'web_signup',
          user_agent: getHeader(event, 'user-agent')
        },
        tenant_settings: {
          timezone: 'UTC',
          currency: 'USD',
          language: 'en'
        }
      }
    )

    console.log('Signup result:', JSON.stringify(result, null, 2))

    // Check if the result is successful
    if (result && result[0] && result[0].result?.success) {
      const signupData = result[0].result

      return {
        success: true,
        message: 'Account created successfully',
        data: {
          user: {
            id: signupData.user.id,
            email: signupData.user.email,
            name: signupData.user.name
          },
          tenant: {
            id: signupData.tenant.id,
            name: signupData.tenant.name,
            slug: signupData.tenant.slug
          },
          membership: signupData.membership
        }
      }
    } else {
      throw createError({
        statusCode: 500,
        statusMessage: 'Signup failed - unexpected response from database'
      })
    }
  } catch (error: unknown) {
    console.error('Signup API error:', error)

    // Handle Zod validation errors
    if (error instanceof z.ZodError) {
      const validationErrors = error.issues
        .map((err) => `${err.path.join('.')}: ${err.message}`)
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
