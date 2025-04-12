export default {
  fetch() {
    const name = "mytestname";
    const now = new Date().toISOString();
    return new Response(JSON.stringify({ name, time: now }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
