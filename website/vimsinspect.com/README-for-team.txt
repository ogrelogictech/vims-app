vimsinspect.com — static site, v1 (October 27, 2026)
=====================================================

WHAT THIS IS
Plain static HTML/CSS. No JavaScript, no build step, no cookies, no third-party requests
(fonts are self-hosted). Upload the whole folder as the web root of vimsinspect.com.

  index.html     Home page
  privacy.html   Privacy Policy (client-approved October 23, 2026 — do not edit the wording)
  support.html   Support page
  site.css       Styles (linked as site.css?v=26; bump the number after any CSS change)
  fonts/         Archivo, IBM Plex Sans, IBM Plex Mono (SIL Open Font License, files included)
  img/           Logo mark and app screenshots (WebP)
  favicon.ico, icon.svg, apple-touch-icon.png, robots.txt, sitemap.xml

HOSTING CHECKLIST
1. Point vimsinspect.com and www.vimsinspect.com at the server (GoDaddy DNS: A record for @,
   CNAME for www). Do NOT touch the MX / email records: the client's four mailboxes
   (masteradmin@, admin@, support@, quality@) run on this domain.
2. HTTPS required (Let's Encrypt or similar). Redirect http -> https and www -> apex.
3. Serve .html files with Content-Type text/html; .woff font/woff; .webp image/webp; .svg image/svg+xml.
4. Cache: fonts/ and img/ can be cached long (1 year); HTML short (5 minutes).
5. Optional nice URLs: /privacy and /support rewriting to the .html files. If you add them,
   update sitemap.xml and use those URLs in the store listings.

URLS FOR THE STORE LISTINGS (once live)
  Privacy Policy:  https://vimsinspect.com/privacy.html
  Support URL:     https://vimsinspect.com/support.html
  Marketing URL:   https://vimsinspect.com/

WHY IT MATTERS NOW
Apple's organization enrollment checks that vimsinspect.com is a live website with real
content. Please get it live before Jeremy's Apple enrollment is reviewed.

CONFIRM WITH THE CLIENT BEFORE GOING LIVE (Gaurav handles)
- Phone (385) 383-7776 is shown publicly (header, contact, support page). It is the mobile
  number from the store requirements sheet.
- Pricing shown: App only $34.95/mo (includes first inspector), additional inspector $24.95/mo,
  pay per report $5.00, web portal + app $64.95/mo marked "Coming soon", 30-day free trial.
- The "Start your 30-day free trial" buttons open an email to support@vimsinspect.com until
  the app is in the stores. When it is, swap them for App Store / Google Play links.
