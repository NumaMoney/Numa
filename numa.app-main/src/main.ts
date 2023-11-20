import '@/assets/styles/index.sass'

import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from '@/App.vue'
import router from '@/router'

// @ts-ignore
const app = createApp(App)

app.use(createPinia())
app.use(router)

app.mount('#app')
