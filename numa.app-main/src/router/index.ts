import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      redirect: '/mint'
    },
    {
      path: '/mint',
      name: 'mint',
      component: () => import('@/pages/PageMint.vue')
    },
    {
      path: '/stake',
      name: 'stake',
      component: () => import('@/pages/PageStake.vue')
    },
    {
      path: '/arbitrage',
      name: 'arbitrage',
      component: () => import('@/pages/PageArbitrage.vue')
    },
    {
      path: '/stats',
      name: 'stats',
      component: () => import('@/pages/PageStats.vue')
    },
  ]
})

export default router