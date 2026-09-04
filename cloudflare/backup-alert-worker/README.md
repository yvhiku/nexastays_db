# Nexa database backup alert receiver

This Cloudflare Worker is the HTTPS webhook destination for the production
database backup job. It accepts only bounded, schema-validated JSON `POST`
requests to `/backup-alert` from the production VPS IPv4 or IPv6 address and
writes structured events to Workers Observability.

Deploy from this directory with `npx wrangler@latest deploy`. The public health
check is `/health`; it exposes no backup data. Do not add credentials to the
Worker source or Wrangler configuration.
