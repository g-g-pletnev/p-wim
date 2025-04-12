export default {
    async fetch(request, env, ctx) {
      return new Response(`Hello from mytestapi at ${new Date().toISOString()}`);
    }
  };
  