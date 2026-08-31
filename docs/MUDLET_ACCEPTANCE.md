# Mudlet Acceptance Checklist

- Install `dist/DragonsGateHUD.mpackage` in a disposable profile first.
- Confirm one left character panel and one right GMCP panel appear.
- Confirm Test Tester, Monitanian, Fighter, HP 201/201, fatigue 69/69, carry 15.9/380, weapon ready, shield ready, Training Center, and east/west exits.
- Run `dghud reload` repeatedly and confirm panels and handlers do not duplicate.
- Record console borders, shut down the HUD, and confirm all four borders are restored.
- Create unrelated trigger, alias, timer, key, script, and package fixtures. Confirm install, reload, update failure, and removal leave every fixture unchanged.
- Test package download failure, checksum failure, and health-check failure; confirm the working HUD remains active or rolls back.
- Do not publish until every item above passes in Mudlet 5.0.0 or newer.
