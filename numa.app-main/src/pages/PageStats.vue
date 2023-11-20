<template>
  <div class="page-stats page">
    <div class="title page-stats__title">Statistics</div>

    <div class="page-stats__body">
      <div class="page-stats__box">
        <div class="page-stats__box-subtitle">Burned</div>
        <div class="page-stats__box-title">$numa</div>
        <div class="page-stats__box-value"><span>12412.04</span> $1204.12</div>
      </div>

      <div class="page-stats__box">
        <div class="page-stats__box-subtitle">Burned</div>
        <div class="page-stats__box-title">$nuUSD</div>
        <div class="page-stats__box-value"><span>94777.89</span> $94019.12</div>
      </div>

      <div class="page-stats__box">
        <div class="page-stats__box-subtitle">Burned</div>
        <div class="page-stats__box-title">$nuBTC</div>
        <div class="page-stats__box-value"><span>4.56</span> $125204,83</div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="sass">
.page-stats
  &__title
    font-weight: 600
    margin-bottom: 24px

  &__body
    display: flex
    gap: 16px

  &__box
    @include box

    display: flex
    flex-direction: column
    justify-content: space-between
    gap: 12px
    padding: 16px
    width: 100%

    &-subtitle
      color: var(--color-secondary)
      font-size: 14px

    &-title
      font-size: 30px
      font-weight: 700
      margin-bottom: 4px
      font-family: 'GT Sectra Book'

    &-value
      color: var(--color-secondary)
      font-weight: 500
      font-size: 14px

      span
        font-size: 18px
        color: rgb(46, 112, 255)

  @media screen and (max-width: $breakpointMobile)
    &__body
      flex-direction: column
</style>
<script setup>
</script>