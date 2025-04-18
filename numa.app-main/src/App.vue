<template>
  <main class="main">
    <AppHeader />

    <div class="main__content container">
      <RouterView />
    </div>

    <AppModal />
  </main>
</template>

<script setup>
import AppHeader from '@/modules/AppHeader/AppHeader.vue'
import AppModal from '@/modules/AppModal/AppModal.vue'
</script>

<style lang="sass">
.main
  &__content
    display: flex
    flex-direction: column
    align-items: center
    margin: 0 auto
    padding: 0 24px

  @media screen and (max-width: $breakpointMobile)
    &__content
      padding: 0 20px
</style>