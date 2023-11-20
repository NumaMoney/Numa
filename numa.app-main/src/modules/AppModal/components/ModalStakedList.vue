<template>
  <div class="modal-staked-list modal__body">
    <div class="modal__title">Staked Tokens</div>

    <div class="modal-staked-list__body">
      <div class="modal-staked-list__nothing">
        You haven't staked yet...
      </div>
    </div>

    <div class="modal-staked-list__buttons">
      <Button is-disabled class="modal-staked-list__buttons-button">Withdraw</Button>
    </div>
  </div>
</template>

<script setup>
import Input from '@/ui/Input.vue'
import Button from '@/ui/Button.vue'
</script>

<style scoped lang="sass">
.modal-staked-list
  padding: 20px 20px

  &__nothing
    color: var(--color-secondary)

  &__buttons
    margin-top: 24px

    &-button
      width: 100%
</style>