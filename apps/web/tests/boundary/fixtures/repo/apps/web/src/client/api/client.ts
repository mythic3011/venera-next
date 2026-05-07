export function createRuntimeApiClient() {
  return {
    getHealth() {
      return Promise.resolve({
        status: "open",
      });
    },
  };
}
