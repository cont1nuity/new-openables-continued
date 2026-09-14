# New Openables - Continued

## Creates a single bar for openable / usable items currently in the players bags.

Continued version of the Original [New Openables](https://www.curseforge.com/wow/addons/new-openables) and the maintenance project by [srhinos](https://github.com/srhinos/new-openables) to support Dragonflight.


Add-on scan bags for items to use, open, learn etc. When find new proper item it put it  on button like action bars. For "Quest Items" create extra button bar what complement click-able button in "Quest watch frame". Adventage are 1st buttons are always at same place, 2nd are bigger and last added/used and 3rd quest item have hot-key assigned.

Features: 

 - Create single button to click on to combine/open/use/lockpick item in bags.
 - Button can have assigned hot-key to be able use keyboard short-cut.
 - When click to use item add-on will continue to scan bags and change to next usable item in your inventory.
 - Is possible skip item (remove from button) by right-click, when no other items are found then all skipped items are placed back on button.
 - Is possible permanently blacklist item (remove from button) by CTRL right-click, this permanent blacklist can be cleared via slash command "/nop clear" or from Game Menu, Interface, AddOns.
 - Is possible remove permanently blacklisted item just one with /nop unlist itemID. ItemID come from query via /nop list.
 - Quest items. For each quest item in bags is added separate button. This part is taken from Quest Item Bar made by Nickenyfiken and ZidayaXis. I loved that add-on and original authors have no plans to maintain it. I did adopted core functionality from that add-on.
 - Auto-accept and auto-turnin quests from new Quest Tracker.
 - Integrates the item button with Blizzard Edit Mode, including per-layout positioning.

Supported items: 

 - Many items, list did grow by time I think is time just say "many" here :)
 - Rogues have placed locked lock-boxes on button, according to level of lock-picking skill. 1st click lock-pick and second click open.
 - Items used for standing gain, be warned addon deosn't check actual standing so if item is consumed on exalted staning it become void. This is not a problem for Legion Tokens because these can be used past Exalted as well.
 - Dragonflight profession knowledge items.

Let me know item names to add to wish list. I will grow list as I find items suitable to add. Please I need people who will send me translations for nop-locale-enUS.lua to other languages. Localized SubZones are in for deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN and zhTW.

Original idea behind this add-on come from Driizt@BB_EU who did make single button for all items containing description "Use: Open ....", I did extend it into all usable items.

Blizzard Edit Mode integration uses the EditModeExpanded-1.0 library by Teelo, included with permission under the library's distribution terms.


Known issues: 

 - Most likely missing lots of the Dragonflight profession knowledge items.

Source pulled from [this curseforge](https://www.curseforge.com/wow/addons/new-openables) project as the author has since abandoned it.
Afterwards forked from srhinos maintenance repo at https://github.com/srhinos/new-openables/
