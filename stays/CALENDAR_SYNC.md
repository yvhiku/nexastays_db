# Calendar sync (iCal Phase 1)

See also monorepo `docs/ECOSYSTEM_ARCHITECTURE.md` (calendar sync section).

## Precedence

1. Nexa booking  
2. HOST block  
3. ADMIN block  
4. ICAL block  
5. Available  

## Migration

Run `020_ical_calendar_sync.sql` via `database/stays/migrate.ps1`.

## Host APIs

- `GET/POST /stays/host/listings/:id/external-calendars`
- `PATCH/DELETE .../external-calendars/:calId`
- `POST .../external-calendars/:calId/sync` (30s cooldown)
- `GET .../calendar-export` / `POST .../calendar-export/regenerate`
- Public `GET /stays/calendar/:token[.ics]`
