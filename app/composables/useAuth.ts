export const useAuth = () => {
  const { authenticate, sql } = useSurrealDB({ database: 'default' })

  const getCurrentUserData = async (token: string) => {
    try {
      if (!isvalidToken(token)) return null

      const { data } = await sql(`select * from $session`)

      const valueArray = data?.value ?? []
      return valueArray[0]?.result?.[0] ?? null
    } catch (error) {
      console.error('Failed to get current user:', error)
      return null
    }
  }

  const isvalidToken = async (token: string) => {
    try {
      await authenticate(token)
      return true
    } catch {
      return false
    }
  }

  return {
    getCurrentUserData,
    isvalidToken
  }
}
