<template>
  <header class="header">
    <div class="header__inner">
      <router-link to="/">
        <Image src="./images/logo.svg" class="header__logo" />
      </router-link>

      <div v-if="!layoutStore.isMobile" class="header__tabs">
        <router-link v-for="tab in tabs" :to="tab.route" class="header__tabs-tab hover-opacity">{{ tab.title }}</router-link>
      </div>

      <div class="header__buttons">
        <Button class="header__buttons-button">Connect</Button>

        <Image
          v-if="layoutStore.isMobile"
          :src="isMenuVisible ? './images/icons/close.svg' : './images/icons/menu.svg'"
          class="header__buttons-menu"
          @click="isMenuVisible = !isMenuVisible"
        />
      </div>
    </div>

    <HeaderMenu v-if="isMenuVisible" :tabs="tabs" @closeMenu="isMenuVisible = false" />
  </header>
</template>

<script setup>
import Image from '@/ui/Image.vue'
import Button from '@/ui/Button.vue'
import HeaderMenu from '@/modules/AppHeader/components/HeaderMenu.vue'

import { ref } from 'vue'
import { useLayoutStore } from '@/stores'

const layoutStore = useLayoutStore()

const isMenuVisible = ref(false)
const tabs = ref([
  {
    title: 'Mint',
    route: '/mint'
  },

  {
    title: 'Stake',
    route: '/stake'
  },

  {
    title: 'Arbitrage',
    route: '/arbitrage'
  },

  {
    title: 'Stats',
    route: '/stats'
  },
])
</script>

<style scoped lang="sass">
.header
  position: relative
  width: 100%
  margin-bottom: 48px
  //backdrop-filter: blur(8px)
  //background-color: rgba(13, 14, 18, 0.95)

  &__inner
    padding: 24px 24px
    display: flex
    justify-content: space-between
    align-items: center

  &__logo
    height: 24px

  &__tabs
    display: flex
    gap: 16px

    &-tab
      cursor: pointer
      position: relative
      padding: 12px 0
      user-select: none

      &.router-link-active
        &:after
          content: ''
          position: absolute
          bottom: 0
          left: 0

          height: 1px
          background-color: white
          width: 100%

  &__buttons
    display: flex
    align-items: center
    gap: 16px

    &-menu
      height: 30px
      width: 30px
      cursor: pointer
</style>