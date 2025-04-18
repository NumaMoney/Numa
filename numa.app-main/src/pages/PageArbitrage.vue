<template>
  <div class="page-arbitrage page page--centered">
    <div class="page-arbitrage__header">
      <div class="page-arbitrage__box page-arbitrage__header-box --first" @click="onStatsClick">
        <div class="page-arbitrage__box-title">$nuUSD</div>
        <div class="page-arbitrage__box-value">$0.98</div>
      </div>

      <div class="page-arbitrage__box page-arbitrage__header-box" @click="onStatsClick">
        <div class="page-arbitrage__box-title">$nuBTC</div>
        <div class="page-arbitrage__box-value">$27018.20 <span>Market: $27442.13</span></div>
      </div>
    </div>

    <SwapperArbitrage />
  </div>
</template>

<script setup>
import SwapperArbitrage from '@/components/SwapperArbitrage.vue'
import { useRouter } from 'vue-router'

const router = useRouter()

function onStatsClick() {
  router.push('/stats')
}
</script>

<style scoped lang="sass">
.page-arbitrage
  &__header
    display: flex
    justify-content: space-between
    gap: 16px
    max-width: 480px
    width: 100%
    margin-bottom: 24px

    &-box
      width: 100%

  &__box
    @include box

    display: flex
    flex-direction: column
    justify-content: space-between
    gap: 12px
    padding: 16px
    cursor: pointer
    transition: opacity 0.3s ease

    &.--first
      max-width: 40%

    &:hover
      opacity: 0.7

    &-title
      font-family: 'GT Sectra Book'
      font-size: 24px
      font-weight: 700
      margin-bottom: 8px

    &-value
      color: var(--color-secondary)
      font-weight: 500

      span
        font-size: 12px
        white-space: nowrap

  @media screen and (max-width: $breakpointMobile)
    &__box
      &.--first
        max-width: 100%
</style>