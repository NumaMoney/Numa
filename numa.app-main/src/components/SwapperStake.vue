<template>
  <div class="swapper-stake swapper">
    <div class="swapper__header">
      <div class="swapper__header-title title">Add Liquidity & Stake</div>

      <div class="swapper__header-actions">
        <Image src="./images/icons/list.svg" class="swapper__header-action hover-opacity" @click="onListClick" />
      </div>
    </div>

    <div class="swapper__description">
      <div class="swapper__description-point">Unclaimed Rewards: <b>99.32 $nuUSD</b></div>
      <div class="swapper__description-point">End of Incentive: <b>21/10/2023 at 3:00 UTC</b></div>
    </div>

    <div class="swapper__section">
      <div class="swapper__section-header">
        <span>Asset 1:</span>

        <span>Your balance: 0</span>
      </div>

      <div class="swapper__section-body">
        <input type="number" min="0" placeholder="Enter value" class="swapper__section-input" />

        <div class="swapper__token hover-opacity" @click="onTokenClick">
          <Image src="./images/logo-squared.jpeg" class="swapper__token-image" />

          <div class="swapper__token-title">nuUSD</div>

          <Image src="./images/icons/arrow-down.svg" class="swapper__token-arrow" />
        </div>
      </div>
    </div>

    <div class="swapper__center">
      <Image src="./images/icons/swap.svg" class="swapper__center-image hover-opacity" />
    </div>

    <div class="swapper__section">
      <div class="swapper__section-header">
        <span>Asset 2:</span>

        <span>Your balance: 0</span>
      </div>

      <div class="swapper__section-body">
        <input type="number" disabled min="0" placeholder="Calculating..." class="swapper__section-input" />

        <div class="swapper__token hover-opacity" @click="onTokenClick">
          <Image src="./images/icons/eth.svg" class="swapper__token-image" />

          <div class="swapper__token-title">ETH</div>

          <Image src="./images/icons/arrow-down.svg" class="swapper__token-arrow" />
        </div>
      </div>
    </div>

    <div class="swapper__buttons">
      <Button class="swapper__buttons-button">Connect Wallet</Button>
    </div>
  </div>
</template>

<script setup>
import Image from '@/ui/Image.vue'
import Button from '@/ui/Button.vue'

import { useLayoutStore } from '@/stores'

const layoutStore = useLayoutStore()

function onTokenClick() {
  layoutStore.openModal('ChooseToken')
}

function onListClick() {
  layoutStore.openModal('StakedList')
}
</script>

<style scoped lang="sass">
@import '@/assets/styles/components/swapper'
</style>