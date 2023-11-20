<template>
  <div class="header-menu">
    <div class="header-menu__body">
      <router-link
        v-for="tab in tabs"
        :to="tab.route"
        class="header-menu__item"
        @click="emit('closeMenu')"
      >
        {{ tab.title }}
      </router-link>
    </div>
  </div>
</template>

<script setup>
defineProps({
  tabs: {
    type: Array,
    required: true
  }
})

const emit = defineEmits(['closeMenu'])
</script>

<style scoped lang="sass">
.header-menu
  position: fixed
  width: 100%
  height: 100%
  min-height: 1000px
  left: 0
  background-color: var(--background-primary)
  border-top: 1px solid rgb(85, 86, 90)
  z-index: 100
  animation: fadeIn 0.3s ease

  &__body
    display: flex
    flex-direction: column
    gap: 24px
    padding: 24px 24px

  &__item
    font-size: 26px
    cursor: pointer

</style>