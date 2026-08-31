# Hybrid HUD acceptance

Use only the disposable `Dragons Gate HUD` profile.

1. Install the package and confirm Identity and Character/Combat are left, Vitals/Location are lower-left, and Equipment/Wealth/Inventory are right.
2. Enter a character and confirm exactly one sequential `inventory`, `stat`, `info` refresh.
3. Compare inventory, exact readied equipment, attributes, physical details, armor, OR/DR, movement, damage bonus, stance, and novice protection with command output.
4. Run each command manually and confirm its HUD section refreshes.
5. Confirm available compass directions are bright and clickable; unavailable directions are dim and inert.
6. In a safe test room, verify `GO PORTAL`, `GO DOOR`, `GO GATE`, and `GO ARCH` send their exact commands.
7. Resize through wide, medium, compact, high-resolution, and back. Confirm text remains readable, no card clips a complete row, and the main console retains at least 64% width.
8. Run `dghud reload` repeatedly and confirm panels and handlers do not duplicate.
9. Run `lua display({version=DGHUD.settings.version,healthy=DGHUD.healthCheck()})` and confirm the installed version and `healthy=true`.
10. Confirm unrelated packages, scripts, triggers, aliases, and profile settings remain unchanged after install, reload, update failure, and removal.
