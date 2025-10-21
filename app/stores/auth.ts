import { defineStore } from 'pinia'

export const useAuthStore = defineStore('auth', {
  state: () => ({
    token: ''
  }),
  actions: {
    logout() {
      this.token = ''
    },
    login(token: string) {
      this.token = token
    }
  }
})
