<template>
  <div v-show="layoutStore.modalName" class="modal">
    <div ref="content" class="modal__content">
      <Image
        src="./images/icons/close.svg"
        class="modal__close hover-opacity"
        @click="closeModal"
      />

      <Component
        :is="modal"
        v-bind="layoutStore.modalProps"
        @closeModal="closeModal"
      />
    </div>
  </div>
</template>

<script setup>
import Image from '@/ui/Image.vue'

import { computed, defineAsyncComponent, ref, watch } from 'vue'
import { onClickOutside } from '@vueuse/core'
import { useLayoutStore } from '@/stores'
import { useRoute } from 'vue-router'

const layoutStore = useLayoutStore()
const route = useRoute()

const content = ref(null)
const modal = computed(() => {
  const modalName = layoutStore.modalName

  if (!modalName) {
    return null
  }

  return defineAsyncComponent(() => import(`@/modules/AppModal/components/Modal${modalName}.vue`))
})

onClickOutside(content, closeModal)

watch(() => route.fullPath, layoutStore.closeModal)

function closeModal() {
  layoutStore.closeModal()
}
</script>

<style lang="sass">
.modal
  position: fixed
  top: 0
  left: 0
  width: 100%
  height: 100%
  display: flex
  justify-content: center
  align-items: center
  background-color: rgba(13, 14, 18, 0.8)
  animation: fadeIn 0.3s ease

  &__content
    max-width: 460px
    width: 100%
    border: 1px solid rgb(34, 34, 38)
    border-radius: 10px
    background: rgb(34, 34, 38)
    position: relative

  &__close
    position: absolute
    top: 22px
    right: 22px
    height: 22px
    width: 22px
    cursor: pointer
    color: var(--color-secondary)

  &__title
    font-family: 'GT Sectra Book', sans-serif
    font-size: 24px
    margin-bottom: 20px

  &__body
    display: flex
    flex-direction: column

  @media screen and (max-width: $breakpointMobile)
    &__content
      position: fixed
      bottom: 0
      width: 100%
      border-radius: 12px 12px 0 0
      animation: fadeInUp 0.3s ease
</style>