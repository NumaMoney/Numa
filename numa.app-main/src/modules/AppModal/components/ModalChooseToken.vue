<template>
  <div class="modal-choose-token modal__body">
    <div class="modal-choose-token__header">
      <div class="modal__title">Choose Token</div>

      <Input
        icon="./images/icons/search.svg"
        placeholder="Search by token name"
        class="modal-choose-token__search"
      />
    </div>

    <div class="modal-choose-token__body scrollbar-hidden">
      <div class="modal-choose-token__token">
        <Image src="./images/logo-squared.jpeg" class="modal-choose-token__token-logo" />

        <div class="modal-choose-token__token-info">
          <div class="modal-choose-token__token-title">numa</div>
          <div class="modal-choose-token__token-symbol">numa</div>
        </div>
      </div>

      <div class="modal-choose-token__token">
        <Image src="./images/logo-squared.jpeg" class="modal-choose-token__token-logo" />

        <div class="modal-choose-token__token-info">
          <div class="modal-choose-token__token-title">numa Bitcoin</div>
          <div class="modal-choose-token__token-symbol">nuBTC</div>
        </div>
      </div>

      <div class="modal-choose-token__token">
        <Image src="./images/logo-squared.jpeg" class="modal-choose-token__token-logo" />

        <div class="modal-choose-token__token-info">
          <div class="modal-choose-token__token-title">numa USD</div>
          <div class="modal-choose-token__token-symbol">nuUSD</div>
        </div>
      </div>

      <div class="modal-choose-token__token">
        <Image src="./images/icons/eth.svg" class="modal-choose-token__token-logo" />

        <div class="modal-choose-token__token-info">
          <div class="modal-choose-token__token-title">Ethereum</div>
          <div class="modal-choose-token__token-symbol">ETH</div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import Input from '@/ui/Input.vue'
import Image from '@/ui/Image.vue'
</script>

<style scoped lang="sass">
.modal-choose-token
  max-width: 650px
  max-height: 580px
  width: 100%

  &__header
    padding: 20px 20px
    border-bottom: 1px solid rgb(85, 86, 90)

  &__token
    display: flex
    padding: 16px 20px
    cursor: pointer

    &:hover
      background-color: #ffffff10

    &-logo
      height: 36px
      width: 36px
      min-height: 36px
      min-width: 36px
      border-radius: 50%
      margin-right: 12px

    &-title
      font-size: 16px
      margin-bottom: 4px

    &-symbol
      color: var(--color-secondary)

  &__body
    overflow-y: scroll
</style>