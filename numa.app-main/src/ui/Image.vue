<template>
  <InlineSvg v-if="props.src.includes('.svg')" :src="props.src"></InlineSvg>
  <img v-else :src="props.src" :alt="props.alt" />
</template>

<script setup lang="ts">
import InlineSvg from 'vue-inline-svg'

const props = defineProps({
  src: {
    type: String,
    required: true,
  },

  alt: {
    type: String,
  },
})
</script>

<style lang="sass">
svg
  path:not([fill]),
  rect:not([fill]),
  g:not([fill])
    fill: currentColor
</style>