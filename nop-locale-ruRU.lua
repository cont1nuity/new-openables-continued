-- Translator ZamestoTV
local _
-- global functions and variebles to locals to keep LINT happy
local assert = _G.assert
local LibStub = _G.LibStub; assert(LibStub ~= nil,'LibStub')
-- local AddOn
local ADDON = ...
local AceLocale = LibStub:GetLibrary("AceLocale-3.0");
local L = AceLocale:NewLocale(ADDON, "ruRU");
if not L then return end
--
L["NOP_TITLE"] = "Новые открываемые"
L["NOP_VERSION"] = "|cFFFFFFFF%s используйте |cFFFF00FF/nop|cFFFFFFFF"
L["CLICK_DRAG_MSG"] = "ALT+ЛКМ и перетаскивание для перемещения."
L["CLICK_OPEN_MSG"] = "ЛКМ — открыть или использовать."
L["CLICK_SKIP_MSG"] = "ПКМ — пропустить предмет."
L["CLICK_BLACKLIST_MSG"] = "CTRL+ПКМ — добавить в чёрный список навсегда."
L["No openable items!"] = "Нет открываемых предметов!"
L["BUTTON_RESET"] = "Сбросить и переместить кнопку в центр экрана!"
L["NOP_USE"] = "Использование: "
L["Spell:"] = "Заклинание:"
L["BLACKLISTED_ITEMS"] = "|cFFFF00FFПредметы в постоянном чёрном списке:"
L["BLACKLIST_EMPTY"] = "|cFFFF00FFПостоянный чёрный список пуст"
L["PERMA_BLACKLIST"] = "Постоянно в чёрном списке:|cFF00FF00"
L["SESSION_BLACKLIST"] = "В чёрном списке на сессию:|cFF00FF00"
L["TEMP_BLACKLIST"] = "Временно в чёрном списке:|cFF00FF00"
L["|cFFFF0000Error loading tooltip for|r "] = "|cFFFF0000Ошибка загрузки подсказки для|r "
L["Plans, patterns and recipes cache update."] = "Обновление кэша чертежей, выкроек и рецептов."
L["Spell patterns cache update."] = "Обновление кэша заклинаний."
L["|cFFFF0000Error loading tooltip for spell |r "] = "|cFFFF0000Ошибка загрузки подсказки для заклинания |r "
L["|cFFFF0000Error loading tooltip for spellID %d"] = "|cFFFF0000Ошибка загрузки подсказки для spellID %d"
L["TOGGLE"] = "Переключить"
L["Skin Button"] = "Скин кнопки"
L["Masque Enable"] = "Включить Masque"
L["Need UI reload or relogin to activate."] = "Требуется перезагрузка интерфейса или выход/вход в игру."
L["Lock Button"] = "Заблокировать кнопку"
L["Lock button in place to disbale drag."] = "Зафиксировать кнопку на месте, отключив перетаскивание."
L["Glow Button"] = "Свечение кнопки"
L["When item is placed by zone change, button will have glow effect."] = "При появлении предмета от смены зоны кнопка будет подсвечиваться."
L["Backdrop Button"] = "Фон кнопки"
L["Create or remove backdrop around button, need reload UI."] = "Создать или убрать фон вокруг кнопки, требуется перезагрузка интерфейса."
L["Session skip"] = "Пропуск на сессию"
L["Skipping item last until relog."] = "Пропускать предмет до выхода из игры."
L["Clear Blacklist"] = "Очистить чёрный список"
L["Reset Permanent blacklist."] = "Сбросить постоянный чёрный список."
L["Zone unlock"] = "Снять ограничение по зоне"
L["Don't zone restrict openable items"] = "Не ограничивать открываемые предметы по зонам"
L["Profession"] = "Профессия"
L["Place items usable by lockpicking"] = "Размещать предметы, открываемые взломом"
L["Button"] = "Кнопка"
L["Button location"] = "Положение кнопки"
L["Button size"] = "Размер кнопки"
L["Width and Height"] = "Ширина и высота"
L["Button size in pixels"] = "Размер кнопки в пикселях"
L["Miner's Coffee stacks"] = "Стаки кофе шахтёра"
L["Allow buff up to this number of stacks"] = "Разрешить бафф до указанного количества стаков"
L["Quest bar"] = "Панель заданий"
L["Quest items placed on bar"] = "Предметы заданий размещаются на панели"
L["Visible"] = "Видимость"
L["Make button visible by placing fake item on it"] = "Сделать кнопку видимой, разместив на ней фиктивный предмет"
L["Swap"] = "Поменять местами"
L["Swap location of numbers for count and cooldown timer"] = "Поменять местами числа количества и таймера восстановления"
L["AutoQuest"] = "Автопринятие заданий"
L["Auto accept or hand out quests from AutoQuestPopupTracker!"] = "Автоматически принимать или сдавать задания из AutoQuestPopupTracker!"
L["Strata"] = "Слой"
L["Set strata for items button to HIGH, place it over normal windows."] = "Установить высокий слой для кнопки предметов, чтобы она была поверх обычных окон."
L["Herald"] = "Глашатай"
L["Announce completed work orders, artifact points etc.."] = "Оповещать о завершённых заказах, очках артефакта и т.п."
L["Skip on Error"] = "Пропускать при ошибке"
L["Temporary blacklist item when click produce error message"] = "Временно добавлять в чёрный список предмет, если при клике возникает ошибка"
L["HIDE_IN_COMBAT"] = "Скрывать в бою"
L["HIDE_IN_COMBAT_HELP"] = "Скрывать кнопку предметов во время боя"
L["SHOW_REPUTATION"] = "Показывать репутацию"
L["SHOW_REPUTATION_HELP"] = "Показывать статус репутации Легиона в подсказке для токенов. Активация/деактивация требует перезагрузки клиента."
L["SKIP_EXALTED"] = "Пропускать при почтении"
L["SKIP_EXALTED_HELP"] = "Не использовать токены репутации Легиона, если уже достигнуто почтение."
L["SKIP_MAXPOWER"] = "Пропускать артефакт"
L["SKIP_MAXPOWER_HELP"] = "Пропускать токены силы артефакта, если артефакт имеет максимум черт."
L["Buttons per row"] = "Кнопок в ряду"
L["Number of buttons placed in one row"] = "Количество кнопок в одном ряду"
L["Spacing"] = "Отступы"
L["Space between buttons"] = "Расстояние между кнопками"
L["Sticky"] = "Прилипание"
L["Anchor to Item button"] = "Привязка к кнопке предмета"
L["Direction"] = "Направление"
L["Expand bar to"] = "Расширять панель в"
L["Up"] = "Вверх"
L["Down"] = "Вниз"
L["Left"] = "Влево"
L["Right"] = "Вправо"
L["Add new row"] = "Добавить ряд"
L["Above or below last one"] = "Над или под последним"
L["Hot-Key"] = "Горячая клавиша"
L["Key to use for automatic key binding."] = "Клавиша для автоматической привязки."
L["Quest"] = "Задание"
L["Quest not found for this item."] = "Задание для этого предмета не найдено."
L["Items cache update run |cFF00FF00%d."] = "Обновление кэша предметов, запуск |cFF00FF00%d."
L["Spells cache update run |cFF00FF00%d."] = "Обновление кэша заклинаний, запуск |cFF00FF00%d."
L["TOGO_ANNOUNCE"] = "%s: %d сделано, %d осталось!"
L["REWARD_ANNOUNCE"] = "Награда за парагон для %s готова!"
L["SHIPYARD_ANNOUNCE"] = "Верфь: %d/%d кораблей!"
L["ARTIFACT_ANNOUNCE"] = "%s: %d черт готовы!"
L["ARCHAELOGY_ANNOUNCE"] = "Археология: %s готова!"
L["TALENT_ANNOUNCE"] = "%s готово!"
L["RESTARTED_LOOKUP"] = "Временный чёрный список очищен, перезапуск поиска!"
L["CONSOLE_USAGE"] = [=[ [reset|skin|lock|clear|list|unlist|skip|glow|zone|quest|show|add]
reset  - сбросить положение кнопки в центр экрана
skin   - переключить скин кнопки
lock   - зафиксировать/разблокировать кнопку
clear  - очистить постоянный чёрный список
list   - показать предметы в постоянном чёрном списке
unlist - удалить предмет из чёрного списка по itemID
skip   - переключить пропуск ПКМ (временно или до выхода)
glow   - включить свечение кнопки при предметах зоны
zone   - переключить ограничение по зонам
quest  - переключить панель заданий
show   - показать пустую кнопку
add    - добавить 'itemID [количество]' в список предметов]=];
