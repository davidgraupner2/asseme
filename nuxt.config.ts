// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  modules: [
    '@nuxt/eslint',
    '@nuxt/image',
    '@nuxt/ui',
    '@nuxt/content',
    '@vueuse/nuxt',
    'nuxt-og-image',
    'nuxt-surrealdb',
    '@pinia/nuxt',
    'pinia-plugin-persistedstate/nuxt'
  ],

  devServer: {
    https: {
      key: './certs/key.pem', // Path to your SSL key file
      cert: './certs/cert.pem' // Path to your SSL certificate file
    }
  },

  $development: {
    surrealdb: {
      databases: {
        default: {
          host: '',
          ws: '',
          NS: '',
          DB: ''
        }
      },
      server: {
        databases: {
          default: {
            auth: {
              user: '',
              pass: ''
            }
          }
        }
      }
    }
  },

  devtools: {
    enabled: true
  },

  css: ['~/assets/css/main.css'],

  content: {
    experimental: { sqliteConnector: 'native' }
  },

  routeRules: {
    '/docs': { redirect: '/docs/getting-started', prerender: false },
    '/api/**': {
      cors: true
    }
  },

  compatibilityDate: '2024-07-11',

  nitro: {
    prerender: {
      routes: ['/'],
      crawlLinks: true
    }
  },

  eslint: {
    config: {
      stylistic: {
        commaDangle: 'never',
        braceStyle: '1tbs'
      }
    }
  }
})
