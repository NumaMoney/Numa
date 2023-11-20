<template>
  <div class="modal-settings modal__body">
    <div class="modal__title">Settings</div>

    <div class="modal-settings__body">
      <div class="modal-settings__input">
        <div class="modal-settings__input-title">Slippage tolerance</div>
        <Input is-number placeholder="Up to 50%" />
      </div>
    </div>

    <div class="modal-settings__buttons">
      <Button class="modal-settings__buttons-button">Save Changes</Button>
    </div>
  </div>
</template>

<script setup>
import Input from '@/ui/Input.vue'
import Button from '@/ui/Button.vue'
</script>

<style scoped lang="sass">
.modal-settings
  padding: 20px 20px

  &__input
    &-title
      font-size: 14px
      margin-bottom: 10px

  &__buttons
    margin-top: 24px

    &-button
      width: 100%
</style>