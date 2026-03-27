module.exports = {
  apps: [
    {
      name: "cocxy-web",
      script: "server.js",
      cwd: "/home/bitnami/web",
      instances: "max",
      exec_mode: "cluster",
      env: {
        NODE_ENV: "production",
        PORT: 3000,
      },
      max_memory_restart: "256M",
      log_date_format: "YYYY-MM-DD HH:mm:ss",
    },
  ],
};
