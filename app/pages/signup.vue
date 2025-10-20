<script setup lang="ts">
import * as z from 'zod'
import type { FormSubmitEvent } from '@nuxt/ui'

definePageMeta({
  layout: 'auth'
})

useSeoMeta({
  title: 'Sign up',
  description: 'Create an account to get started'
})

const toast = useToast()

const fields = [
  {
    name: 'company_name',
    type: 'text' as const,
    label: 'Company Name',
    placeholder: 'Enter your company name'
  },
  {
    name: 'name',
    type: 'text' as const,
    label: 'Name',
    placeholder: 'Enter your name'
  },
  {
    name: 'email',
    type: 'text' as const,
    label: 'Email',
    placeholder: 'Enter your email'
  },
  {
    name: 'password',
    label: 'Password',
    type: 'password' as const,
    placeholder: 'Enter your password'
  }
]

const schema = z.object({
  company_name: z.preprocess((val) => val || '', z.string().min(1, 'Company Name is required')),
  name: z.preprocess((val) => val || '', z.string().min(1, 'Name is required')),
  email: z.preprocess((val) => val || '', z.email().min(1, 'Email is required')),
  password: z.preprocess((val) => val || '', z.string().min(8, 'Must be at least 8 characters'))
})

type Schema = z.output<typeof schema>

async function onSubmit(event: FormSubmitEvent<Schema>) {
  try {
    const formData = event.data

    console.log('Submitting signup for:', formData.email)

    // Call the strongly typed API route
    const response = await $fetch('/api/auth/signup', {
      method: 'POST',
      body: {
        company_name: formData.company_name,
        name: formData.name,
        email: formData.email,
        password: formData.password
      }
    })

    console.log('Signup result:', response)

    toast.add({
      title: 'Success!',
      description: `Welcome ${formData.name}! Your account has been created.`,
      color: 'success'
    })

    await navigateTo('/login')
  } catch (error: unknown) {
    console.error('Signup error:', error)

    let errorMessage = 'Failed to create account. Please try again.'

    // Handle fetch errors from our typed API
    if (error && typeof error === 'object' && 'data' in error) {
      const fetchError = error as { data?: { message?: string } }
      if (fetchError.data?.message) {
        errorMessage = fetchError.data.message
      }
    } else if (error && typeof error === 'object' && 'message' in error) {
      errorMessage = (error as { message: string }).message
    }

    toast.add({
      title: 'Error',
      description: errorMessage,
      color: 'error'
    })
  }
}
</script>

<template>
  <UAuthForm
    :fields="fields"
    :schema="schema"
    title="Create an account"
    :submit="{ label: 'Create account' }"
    @submit="onSubmit"
  >
    <template #description>
      Already have an account? <ULink to="/login" class="text-primary font-medium">Login</ULink>.
    </template>

    <template #footer>
      By signing up, you agree to our
      <ULink to="/" class="text-primary font-medium">Terms of Service</ULink>.
    </template>
  </UAuthForm>
</template>
