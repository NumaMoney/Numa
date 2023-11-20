<template>
  <button class="button" :class="buttonClasses">
    <Image v-if="props.icon" :src="props.icon" class="button__icon" />

    <span class="button__text">
      <slot />
    </span>
  </button>
</template>

<script setup lang="ts">
import Image from '@/ui/Image.vue'
import { computed } from 'vue'

const props = defineProps({
  isDisabled: {
    type: Boolean,
    default: false,
  },

  isPrimary: {
    type: Boolean,
    default: false
  },

  isSecondary: {
    type: Boolean,
    default: false
  },

  icon: {
    type: String,
  },
})

const buttonClasses = computed(() => {
  return {
    '--disabled': props.isDisabled,
    '--secondary': props.isSecondary,
  }
})
</script>

<style scoped lang="sass">
.button
  user-select: none
  cursor: pointer
  padding: 10px 12px
  font-size: 16px
  white-space: nowrap
  border-radius: 8px
  border: 1px solid transparent
  color: var(--color-button-primary)
  background-color: var(--background-button-primary)
  font-weight: 600
  transition: background-color 0.3s ease, opacity 0.3s ease, color 0.3s ease

  &:hover
    color: var(--color-primary)
    background-color: var(--background-button-primary-hover)

  &.--secondary
    background-color: transparent
    border: 1px solid var(--background-stroke)
    font-weight: 500

    &:hover
      background-color: var(--background-stroke)

  &.--disabled
    pointer-events: none
    opacity: 0.5

</style>