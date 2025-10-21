export default defineAppConfig({
  ui: {
    colors: {
      primary: 'violet',
      neutral: 'zinc'
    }
  },
  auth: {
    publicPaths: ['/doc', '/pricing', '/blog', '/changelog', '/auth'],
    adminPaths: ['/panel/admin'],
    loginPaths: {
      admin: '/auth/login/admin',
      user: '/auth/login'
    },
    redirects: {
      afterLogin: '/panel/admin',
      afterLogout: '/'
    }
  }
})
