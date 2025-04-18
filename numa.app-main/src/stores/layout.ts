import { defineStore } from 'pinia'

const useLayoutStore = defineStore('layout', () => {
  return {
    isMobile: window.innerWidth <= 768,

    modalName: '',
    modalProps: {},

    openModal(modalName: string, modalProps: object) {
      this.modalName = modalName
      this.modalProps = modalProps
    },

    closeModal() {
      this.modalName = ''
      this.modalProps = {}
    }
  }
})

window.addEventListener('resize', () => {
  const layoutStore = useLayoutStore()
  layoutStore.isMobile = window.innerWidth <= 768
})

export default useLayoutStore