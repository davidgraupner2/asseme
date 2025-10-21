export default defineNuxtRouteMiddleware(async (to, _from) => {
  const appConfig = useAppConfig()
  const { auth } = appConfig

  const adminLoginPath = '/auth/login/admin'

  const { authenticate } = useSurrealDB()

  // Home page - always allow
  if (to.path === '/') return

  const isPublicPath = auth.publicPaths.some((p) => to.path.startsWith(p))
  const isAdminPath = auth.adminPaths.some((p) => to.path.startsWith(p))

  // Allow public routes
  if (isPublicPath) return

  if (isAdminPath) {
    const authStore = useAuthStore()

    if (!authStore.token) {
      return navigateTo(auth.loginPaths.admin)
    }

    try {
      // Validate our auth token
      // - If it fails we prompt for Admin login again
      // - Otherwise user can proceed
      // TODO: Add more checks to ensure this is an admin connection
      await authenticate(authStore.token)
    } catch {
      authStore.logout()
      return navigateTo(adminLoginPath)
    }
  }
})
