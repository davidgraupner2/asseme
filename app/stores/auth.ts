import { defineStore } from 'pinia'

export const useAuthStore = defineStore('auth', {
  state: () => ({
    token: ''
  }),
  actions: {
    async logout() {
      const { invalidate } = useSurrealDB()
      await invalidate()
      this.token = ''
    },
    login(token: string) {
      this.token = token
    }
  },
  persist: {
    storage: piniaPluginPersistedstate.cookies({
      sameSite: 'strict',
      secure: true, // Use HTTPS in production
      httpOnly: false // Needs to be accessible to client
    })
  }
})
