# Run 11 (Fai) lesson candidates

One line each, with the experiment id, as they happen.

- fai-000: The Fai launcher's downloader carries its own certificate roots and ignores
  SSL_CERT_FILE, so `install.sh` fails behind a TLS-intercepting proxy; the documented loopback
  mirror (FAI_RELEASE_BASE_URL) worked with release assets fetched by curl.
- run: The service-principal secret had expired at the start (AADSTS7000222); check it in Step 0
  of every run, as this plan does.
