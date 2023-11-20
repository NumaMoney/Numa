<template>
  <div
    class="input"
    :class="{ '--disabled': isDisabled }"
    @click="onClick"
  >
    <Image v-if="icon" :src="icon" class="input__icon" />

    <input
      ref="field"
      :type="isNumber ? 'number' : 'text'"
      :value="modelValue"
      :placeholder="placeholder"
      :disabled="isDisabled"
      class="input__field"
      @input="$emit('update:modelValue', ($event.target as HTMLInputElement)?.value)"
    />
  </div>
</template>

<script setup lang="ts">
import Image from '@/ui/Image.vue'

import { ref } from 'vue'
import type { RefValue } from 'vue/macros'

const props = defineProps({
  modelValue: {
    type: String,
  },

  isNumber: {
    type: Boolean,
    default: false,
  },

  placeholder: {
    type: String,
    default: 'Write something...',
  },

  icon: {
    type: String,
  },

  isDisabled: {
    type: Boolean,
    default: false,
  },
})

defineEmits(['update:modelValue'])

const field = ref<RefValue<any>>(null)

function onClick() {
  field.value.focus()
}
</script>

<style scoped lang="sass">
$placeholderColor: color-mix(in srgb, var(--color-primary) 40%, transparent)

.input
  padding: 12px 16px
  border-radius: 12px
  background-color: var(--background-input)
  border: 1px solid rgb(85, 86, 90)
  transition: border-color 0.3s ease, box-shadow 0.3s ease, background-color 0.3s ease
  display: flex
  align-items: center

  &:not(.--disabled):hover,
  &:not(.--disabled):has(.input__field:focus)
    border-color: white

  &__field
    width: 100%
    font-size: 16px

    &:disabled
      text-overflow: ellipsis
      overflow: hidden
      font-weight: 500

    &::placeholder
      color: $placeholderColor

  &__icon
    height: 16px
    width: 16px
    min-height: 16px
    min-width: 16px
    user-select: none

  &__icon
    margin-right: 8px
    color: $placeholderColor
</style>