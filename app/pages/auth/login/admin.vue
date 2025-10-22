<script setup lang="ts">
import * as z from 'zod'
import type { FormSubmitEvent } from '@nuxt/ui'
import { useAuthStore } from '~/stores/auth'

const { $signin } = useSurrealDB()
const authStore = useAuthStore()
const config = useRuntimeConfig()

// Access the SurrealDB settings
const surrealNamespace = config.public.surrealdb.databases.default.NS
const surrealDatabase = config.public.surrealdb.databases.default.DB

definePageMeta({
  layout: 'auth'
})

useSeoMeta({
  title: 'Admin Login',
  description: 'Login to the admin console to continue'
})

const toast = useToast()

const fields = [
  {
    name: 'userName',
    type: 'text' as const,
    label: 'User Name',
    placeholder: 'Enter your user name',
    required: true
  },
  {
    name: 'password',
    label: 'Password',
    type: 'password' as const,
    placeholder: 'Enter your password',
    required: true
  }
]

const schema = z.object({
  userName: z.preprocess((val) => val || '', z.string().min(1, 'UserName is invalid')),
  password: z.preprocess((val) => val || '', z.string().min(8, 'Must be at least 8 characters'))
})

type Schema = z.output<typeof schema>

async function onSubmit(event: FormSubmitEvent<Schema>) {
  // console.log('🚀 Starting signin process...')

  try {
    const formData = event.data
    // console.log('📝 Form data received:', formData)

    const signInDetails = {
      ns: surrealNamespace,
      db: surrealDatabase,
      user: formData.userName,
      pass: formData.password
    }

    console.log(signInDetails)

    const token = await $signin(signInDetails)

    // Store the token
    authStore.login(token)

    // Handle successful signin
    toast.add({
      title: 'Success!',
      description: 'Admin login successful',
      color: 'success'
    })

    // Redirect to admin dashboard or appropriate page
    await navigateTo('/panel/admin')
  } catch (error: any) {
    toast.add({
      title: 'Login failed. Please try again',
      description: `Status: ${error.statusCode} - ${error.message}`,
      color: 'error'
    })
  }
}
</script>

<template>
  <UAuthForm
    :fields="fields"
    :schema="schema"
    title="Admin Panel Login"
    icon="i-lucide-lock"
    @submit="onSubmit"
  >
    <template #description>
      Don't have an account? <ULink to="/signup" class="text-primary font-medium">Sign up</ULink>.
    </template>

    <template #password-hint>
      <ULink to="/" class="text-primary font-medium" tabindex="-1">Forgot password?</ULink>
    </template>

    <template #footer>
      By signing in, you agree to our
      <ULink to="/" class="text-primary font-medium">Terms of Service</ULink>.
    </template>
  </UAuthForm>
</template>
