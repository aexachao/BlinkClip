# BlinkClip rename log

Record of the P2 cleanup renames (2026-11-12). Every `f_100xxx` function in
`replica/Sources` received a descriptive name derived from its actual behaviour;
there are no placeholder names left — all 553 functions were named by hand or by
a verified generator rule (see `reason` column). Overloads sharing a name are
legal Swift overloads: same name in different types, or different parameter lists.

## 1. `f_100xxx` function renames (553)

| Old | New | Reason | File |
|---|---|---|---|
| `f_100008bc0` | `hidePopover` | manual-review | `BlinkClipCore/FilterBrowserPopover.swift` |
| `f_10000df98` | `rebuildSearchConstraints` | manual-review | `BlinkClip/UI/PanelToolbar.swift` |
| `f_10000e0ec` | `dismissSearch` | manual-review | `BlinkClip/UI/PanelToolbar.swift` |
| `f_10000e4c8` | `searchBarConstraints` | constraints | `BlinkClip/UI/PanelToolbar.swift` |
| `f_10000e74c` | `updateSearchActiveState` | manual-review | `BlinkClip/UI/PanelToolbar.swift` |
| `f_10000ed50` | `makeTitleField` | lazy-factory | `BlinkClip/UI/ReplicaSearchSuggestionsMenu.swift` |
| `f_10000ee38` | `makeImageView` | lazy-factory | `BlinkClip/UI/ReplicaSearchSuggestionsMenu.swift` |
| `f_10000eedc` | `makeStackView` | lazy-factory | `BlinkClip/UI/ReplicaSearchSuggestionsMenu.swift` |
| `f_100010984` | `highlightedTitle` | manual-review | `BlinkClip/UI/SuggestionAttributedTitle.swift` |
| `f_100011138` | `configureWindow` | manual-review | `BlinkClipCore/StackFunctions.swift` |
| `f_1000114ec` | `canBecomeMain` | manual | `BlinkClipCore/StackFunctions.swift` |
| `f_1000114f4` | `canBecomeKey` | manual | `BlinkClipCore/StackFunctions.swift` |
| `f_1000114fc` | `canBecomeKeyOrMain` | manual | `BlinkClipCore/StackFunctions.swift` |
| `f_100011c78` | `beginEditing` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_100011d28` | `cancelEditing` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_1000123d4` | `configureCloseButton` | manual-review | `BlinkClip/UI/ReplicaPreviewAdapter.swift` |
| `f_100013084` | `makeTextField` | lazy-factory | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_1000130fc` | `configureTextField` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_100013240` | `commitEditing` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_100013404` | `constrainTextField` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_1000183e0` | `makeSharingServicePicker` | manual-review | `BlinkClipCore/PreviewSharing.swift` |
| `f_1000298b0` | `detachForEditingIfNeeded` | manual-review | `BlinkClipCore/PreviewPopover.swift` |
| `f_100029a80` | `makePreviewWindow` | manual-review | `BlinkClipCore/PreviewPopover.swift` |
| `f_100029da8` | `closePopover` | manual-review | `BlinkClipCore/PreviewPopover.swift` |
| `f_100029e6c` | `showPopover` | manual-review | `BlinkClipCore/PreviewPopover.swift` |
| `f_100029f60` | `updateSharingType` | manual-review | `BlinkClipCore/PreviewPopover.swift` |
| `f_10003e350` | `updateActiveFieldAppearance` | manual-review | `BlinkClip/UI/PanelToolbar.swift` |
| `f_10003e658` | `toggleSearchActivation` | manual-review | `BlinkClip/UI/PanelToolbar.swift` |
| `f_100040054` | `updateSearchEditorFocus` | manual-review | `BlinkClip/UI/PanelToolbar.swift` |
| `f_100041f9c` | `cachedTextView` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_10004200c` | `makeScroller` | lazy-factory | `BlinkClipCore/SearchInputView.swift` |
| `f_100042090` | `makeClearButton` | lazy-factory | `BlinkClipCore/SearchInputView.swift` |
| `f_10004212c` | `configureClearButton` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_1000424e8` | `subviewConstraints` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_1000429d0` | `clearInput` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_100042a68` | `clearSearchInput` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_100042a78` | `updateInputState` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_100042b50` | `updateClearButtonVisibility` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_100042d64` | `showClearButton` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_100042db0` | `hideClearButton` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_100042dfc` | `hideClearButtonIfNeeded` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_100042fc8` | `configureTextView` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043344` | `currentFocusRingBounds` | getter | `BlinkClipCore/SearchTextScroller.swift` |
| `f_100043418` | `drawFocusRing` | manual-review | `BlinkClipCore/SearchTextScroller.swift` |
| `f_1000434f8` | `redrawFocusRing` | manual-review | `BlinkClipCore/SearchTextScroller.swift` |
| `f_100043508` | `performOnContext` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_1000436a0` | `makePlaceholderField` | lazy-factory | `BlinkClipCore/SearchTextView.swift` |
| `f_10004371c` | `configurePlaceholderLabel` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043904` | `syncPlaceholderFont` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043b74` | `currentCanAcceptFocus` | getter | `BlinkClipCore/SearchTextView.swift` |
| `f_100043c24` | `focusAndSelect` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043d2c` | `updateSelectedRange` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043e4c` | `handleTextChange` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043efc` | `notifyTextChange` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043f0c` | `updateLayout` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043fa0` | `refreshLayout` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_100043fb0` | `validateMenuItem` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_1000440e4` | `menuForEvent` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_10004487c` | `cleanContextMenu` | manual-review | `BlinkClipCore/SearchTextView.swift` |
| `f_1000449e8` | `refreshInputState` | manual-review | `BlinkClipCore/SearchInputView.swift` |
| `f_1000450a8` | `subviewConstraints` | manual-review | `BlinkClipCore/SearchFilterView.swift` |
| `f_100045338` | `updateLayout` | manual-review | `BlinkClipCore/SearchFilterView.swift` |
| `f_1000453e8` | `refreshLayout` | manual-review | `BlinkClipCore/SearchFilterView.swift` |
| `f_100045484` | `notifyClick` | manual-review | `BlinkClipCore/SearchFilterView.swift` |
| `f_100045730` | `makeFiltersButton` | lazy-factory | `BlinkClipCore/SearchField.swift` |
| `f_1000457cc` | `animateFiltersButton` | manual-review | `BlinkClipCore/SearchFieldAnimation.swift` |
| `f_100045c2c` | `makeInput` | lazy-factory | `BlinkClipCore/SearchField.swift` |
| `f_100045d40` | `makeIconImageView` | lazy-factory | `BlinkClipCore/SearchField.swift` |
| `f_100045e54` | `notifyClear` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_100045edc` | `configureFiltersButton` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_1000460b8` | `showFilters` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_10004639c` | `subviewConstraints` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_100046914` | `makeFilterStack` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_100046acc` | `handleFilterEvent` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_100046b10` | `forwardMouseEvent` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_100046e28` | `anchorRect` | manual-review | `BlinkClipCore/SearchSuggestionAnchor.swift` |
| `f_1000471b4` | `focusInput` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_1000472ac` | `updateLayout` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_1000473b4` | `refreshLayout` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_100047450` | `isUndoRedoShortcut` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_1000475fc` | `isUndoRedoKeyEvent` | manual-review | `BlinkClipCore/SearchField.swift` |
| `f_10004795c` | `shouldChangeText` | manual-review | `BlinkClipCore/SearchEditing.swift` |
| `f_100047d8c` | `shouldChangeTextInRange` | manual-review | `BlinkClipCore/SearchEditing.swift` |
| `f_100047ea4` | `notifySelectionChange` | manual-review | `BlinkClipCore/SearchEditing.swift` |
| `f_100048058` | `handleCommandSelector` | manual-review | `BlinkClipCore/SearchEditing.swift` |
| `f_100048128` | `notifyEndEditing` | manual-review | `BlinkClipCore/SearchEditing.swift` |
| `f_1000482c8` | `firstUnicodeScalar` | manual-review | `BlinkClipCore/SearchEditing.swift` |
| `f_10004867c` | `handleCommandSelector` | manual-review | `BlinkClipCore/SearchCommands.swift` |
| `f_1000493ec` | `makeScrollView` | lazy-factory | `BlinkClip/UI/ReplicaSearchSuggestionsMenu.swift` |
| `f_10004a994` | `updateScrollEdgeMasks` | manual-review | `BlinkClip/UI/ReplicaSearchSuggestionsMenu.swift` |
| `f_10004ad10` | `makeGradientLayer` | manual-review | `BlinkClip/UI/ReplicaSearchSuggestionsMenu.swift` |
| `f_10004afcc` | `makeImageView` | lazy-factory | `BlinkClip/UI/ReplicaSearchSuggestionsMenu.swift` |
| `f_10004e064` | `toggleDiagnostics` | manual-review | `BlinkClip/AppMain.swift` |
| `f_10004e8ec` | `relaunchAppAndExit` | manual-review | `BlinkClipCore/DiagnosticsAppActions.swift` |
| `f_1000519f8` | `updateNativeSnippet` | single-call | `BlinkClip/UI/StackSnippetCell.swift` |
| `f_100051ec8` | `snippetLabel` | manual-review | `BlinkClip/UI/StackSnippetText.swift` |
| `f_100053988` | `postPasteKeystroke` | manual-review | `BlinkClip/AppMain.swift` |
| `f_1000546e0` | `iconForFilterKind` | manual-review | `BlinkClip/UI/FilterBrowser.swift` |
| `f_100054b2c` | `symbolForFilterKind` | manual-review | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10007be8c` | `beginPreviewEditing` | manual-review | `BlinkClipCore/ItemPreviewView.swift` |
| `f_10007c080` | `commitPreviewEditing` | manual-review | `BlinkClipCore/ItemPreviewView.swift` |
| `f_10007c1fc` | `cancelPreviewEditing` | manual-review | `BlinkClipCore/ItemPreviewView.swift` |
| `f_100082b90` | `tableHeightConstraint` | manual-review | `BlinkClipCore/StackTableController.swift` |
| `f_100083a20` | `updateTableHeight` | manual-review | `BlinkClipCore/StackTableController.swift` |
| `f_10008468c` | `reverseValues` | manual-review | `BlinkClipCore/StackFunctions.swift` |
| `f_100085230` | `currentCount` | getter | `BlinkClipCore/StackTableController.swift` |
| `f_100085670` | `shouldSelectRow` | manual-review | `BlinkClipCore/StackTableController.swift` |
| `f_100086c10` | `registerPreviewWindow` | manual-review | `BlinkClipCore/PreviewWindows.swift` |
| `f_10008727c` | `setEditingState` | manual-review | `BlinkClipCore/PreviewWindows.swift` |
| `f_10008747c` | `windowForItem` | manual-review | `BlinkClipCore/PreviewWindows.swift` |
| `f_10008764c` | `isEqual` | manual-review | `BlinkClipCore/PreviewWindows.swift` |
| `f_100087864` | `updateTopmostPreview` | manual-review | `BlinkClipCore/PreviewWindows.swift` |
| `f_1000879dc` | `removePreviewWindow` | manual-review | `BlinkClipCore/PreviewWindows.swift` |
| `f_100095228` | `updateCollapsedTabs` | manual-review | `BlinkClip/UI/PanelTabBar.swift` |
| `f_100095ae8` | `scrollCellIntoView` | manual-review | `BlinkClip/UI/PanelTabBar.swift` |
| `f_10009ac24` | `scrollRectIntoView` | manual-review | `BlinkClip/UI/PanelTabBar.swift` |
| `f_1000d4624` | `makeNamedDiagnostic` | manual-review | `BlinkClipCore/LocalDiagnostics.swift` |
| `f_1000d468c` | `diagnosticSink` | manual-review | `BlinkClipCore/LocalDiagnostics.swift` |
| `f_1000d48fc` | `consoleLogConfiguration` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d4958` | `makeConsoleLogConfiguration` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d4994` | `fileLogOutput` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d49e8` | `makeFileLogOutput` | factory | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d4a94` | `diagnosticSink` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d4c18` | `makeSystemLogOutput` | factory | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d4db8` | `emitDebug` | manual | `BlinkClipCore/LocalDiagnostics.swift` |
| `f_1000d4dd4` | `emitInfo` | manual | `BlinkClipCore/LocalDiagnostics.swift` |
| `f_1000d4df0` | `emitError` | manual | `BlinkClipCore/LocalDiagnostics.swift` |
| `f_1000d4e0c` | `emitFault` | manual | `BlinkClipCore/LocalDiagnostics.swift` |
| `f_1000d4e28` | `makeLoggingQueue` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d4fc0` | `emit` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d5160` | `emitToOutputs` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d55cc` | `currentLevel` | getter | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d55fc` | `setLevel` | setter | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d56f8` | `setDirectoryURL` | setter | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d5840` | `makeTimestampFormat` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d5aec` | `appendLogEntry` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d682c` | `close` | verb-call | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d6ad0` | `emitToSystemLog` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d6c8c` | `loggerForName` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d6e90` | `setLogger` | manual-review | `BlinkClipCore/DiagnosticDispatcher.swift` |
| `f_1000d80e0` | `resolveDependency` | manual-review | `BlinkClipCore/SharedDependencyCache.swift` |
| `f_1000d8388` | `cachedValue` | manual-review | `BlinkClipCore/Dependencies.swift` |
| `f_1000d83a8` | `registerFactory` | manual-review | `BlinkClipCore/Dependencies.swift` |
| `f_1000d84ac` | `valueForKeyPath` | manual-review | `BlinkClipCore/Dependencies.swift` |
| `f_1000d8600` | `removeFactory` | manual-review | `BlinkClipCore/Dependencies.swift` |
| `f_1000d86bc` | `withOverrides` | single-call | `BlinkClipCore/SharedDependencyCache.swift` |
| `f_1000d8d80` | `registerOverride` | manual-review | `BlinkClipCore/SharedDependencyCache.swift` |
| `f_1000d8e10` | `removeOverride` | manual-review | `BlinkClipCore/SharedDependencyCache.swift` |
| `f_1000d8e88` | `removeAllOverrides` | manual-review | `BlinkClipCore/SharedDependencyCache.swift` |
| `f_1000da458` | `valueWithOverrides` | manual-review | `BlinkClipCore/Dependencies.swift` |
| `f_1000da760` | `valueWithOverrides` | manual-review | `BlinkClipCore/Dependencies.swift` |
| `f_1000da768` | `resolveValue` | verb-call | `BlinkClipCore/Dependencies.swift` |
| `f_1000daac0` | `cachedValue` | manual-review | `BlinkClipCore/SharedDependencyCache.swift` |
| `f_1000dad10` | `storeValue` | manual-review | `BlinkClipCore/SharedDependencyCache.swift` |
| `f_1000dae58` | `requiredValue` | manual-review | `BlinkClipCore/InitializedValue.swift` |
| `f_1000dafe8` | `currentValue` | getter | `BlinkClipCore/InitializedValue.swift` |
| `f_1000db054` | `setValueOnce` | manual-review | `BlinkClipCore/InitializedValue.swift` |
| `f_1000db2dc` | `memberAtKeyPath` | manual-review | `BlinkClipCore/InitializedValue.swift` |
| `f_1000f35e0` | `platformSerialNumber` | manual-review | `BlinkClipCore/ClipboardSourcePersistence.swift` |
| `f_1000f36ec` | `deviceModelName` | manual-review | `BlinkClipCore/ClipboardSourcePersistence.swift` |
| `f_1000f3e48` | `bodyFont` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1000f3ef4` | `plainTextFont` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1000f3f6c` | `fontWithTraits` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1000f4774` | `sysctlStringValue` | manual-review | `BlinkClipCore/ClipboardSourcePersistence.swift` |
| `f_1000f653c` | `makeSystemImage` | manual-review | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_1000f6874` | `currentText` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_1000f69b0` | `setText` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_1000f6ef8` | `editorAttributedString` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1000f6fec` | `editorTextStorage` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1000f7054` | `setEditorTextStorage` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1000f7138` | `setTextStorage` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1000f7254` | `currentString` | getter | `BlinkClipCore/SearchTextValue.swift` |
| `f_1000f733c` | `setString` | setter | `BlinkClipCore/SearchTextValue.swift` |
| `f_1000f74b8` | `layoutViewSubtree` | manual-review | `BlinkClipCore/PreviewFooter.swift` |
| `f_10019b694` | `shortcutTelemetry` | manual-review | `BlinkClipCore/ShortcutTelemetry.swift` |
| `f_10019b6f0` | `makeShortcutTelemetry` | manual-review | `BlinkClipCore/ShortcutTelemetry.swift` |
| `f_1001bda88` | `diagnosticsActionStopAndCopyLogs` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bdc08` | `diagnosticsStartMessage` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bdd88` | `diagnosticsStartTitle` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bdf08` | `diagnosticsStopMessage` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001be088` | `diagnosticsStopTitle` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001be988` | `editItemToolbarDiscardChanges` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bee08` | `editItemToolbarImageRotateLeft` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bef88` | `editItemToolbarImageRotateRight` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bf108` | `editItemToolbarSaveChanges` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bf288` | `editItemToolbarTextBold` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bf408` | `editItemToolbarTextItalic` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bf588` | `editItemToolbarTextStrikethrough` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001bf708` | `editItemToolbarTextUnderline` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c0788` | `generalActionCancel` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c0f08` | `generalActionCreatePinboard` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c1688` | `generalActionEdit` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c2888` | `generalActionPausePaste` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c2a08` | `generalActionPin` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c3188` | `generalActionRestartPaste` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c3908` | `generalActionSave` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c3f08` | `generalActionShare` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c4208` | `generalActionUnpin` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c4388` | `generalBrowser` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c482c` | `generalCopied` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c4b50` | `generalEnableDirectPaste` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c5838` | `generalPastePaused` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c59b8` | `generalPasteResumed` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c5b38` | `generalPaused` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c6aa4` | `generalUntitled` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c6f44` | `itemTypeColor` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c6f68` | `itemTypeImage` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c6f8c` | `itemTypeLink` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c6fb0` | `itemTypeMultipleFiles` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c7130` | `itemTypeText` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001c7154` | `itemTypeUnknown` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001dac54` | `previewRevealInFinderTitle` | resource-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001dadd4` | `previewUnavailableSubtitle` | resource-key | `BlinkClipCore/UnavailablePreviewLocalization.swift` |
| `f_1001daf54` | `previewUnavailableTitle` | resource-key | `BlinkClipCore/UnavailablePreviewLocalization.swift` |
| `f_1001dbfd4` | `settingsGeneralTitle` | resource-key | `BlinkClipCore/SettingsLocalization.swift` |
| `f_1001e16d4` | `settingsPrivacyTitle` | resource-key | `BlinkClipCore/SettingsLocalization.swift` |
| `f_1001e28d4` | `settingsSoundEffectsTitle` | resource-key | `BlinkClipCore/SettingsLocalization.swift` |
| `f_1001e6b38` | `characterCount` | count-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001e6b58` | `lineCount` | count-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001e6b78` | `wordCount` | count-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001e6b98` | `openInApplication` | manual-review | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001e6c18` | `untilTime` | manual-review | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001e6c38` | `fileCount` | count-key | `BlinkClipCore/PreviewLocalization.swift` |
| `f_1001e7514` | `globalShortcutMonitor` | manual-review | `BlinkClipCore/ShortcutDependencies.swift` |
| `f_1001e752c` | `makeGlobalShortcutMonitor` | factory | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001e7580` | `resolveDependency` | manual-review | `BlinkClipCore/ShortcutDependencies.swift` |
| `f_1001e75e4` | `makeShortcutValidatorService` | factory | `BlinkClipCore/ShortcutDependencies.swift` |
| `f_1001e7d18` | `shortcutForEvent` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e7d58` | `carbonModifierFlags` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e7e50` | `displayLabel` | manual | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e8098` | `keyEquivalentLabel` | manual | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e822c` | `menuKeyLabels` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e8a98` | `functionKeyLabels` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e94d4` | `keyCodeForKey` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e95fc` | `escapeKeyCode` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e9610` | `deleteKeyCode` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e9624` | `forwardDeleteKeyCode` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e9638` | `leftArrowKeyCode` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e964c` | `rightArrowKeyCode` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e9654` | `keyCodes` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e9774` | `modifierLabel` | manual-review | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001e9990` | `codingKeyName` | manual-review | `BlinkClipCore/ShortcutCoding.swift` |
| `f_1001e99d0` | `fromString` | manual-review | `BlinkClipCore/ShortcutCoding.swift` |
| `f_1001e9b00` | `encodeToEncoder` | manual-review | `BlinkClipCore/ShortcutCoding.swift` |
| `f_1001e9cc8` | `displayString` | manual-review | `BlinkClipCore/ShortcutCoding.swift` |
| `f_1001e9d68` | `decodeFromDecoder` | manual-review | `BlinkClipCore/ShortcutCoding.swift` |
| `f_1001ea338` | `dispatchHotKeyEvent` | manual-review | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001ea96c` | `eventHandlerCallback` | manual-review | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001ea9b0` | `removeEventHandler` | manual-review | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001eaa64` | `registerShortcutIgnoringStatus` | manual | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001eae90` | `unregisterShortcut` | manual | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001eb110` | `unregisterEventHotKey` | manual-review | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001eb160` | `removeRegistration` | manual-review | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001eb1e4` | `storeRegistration` | manual-review | `BlinkClipCore/GlobalShortcutMonitor.swift` |
| `f_1001ebc2c` | `isFunctionKeyOrModified` | manual | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001ebce4` | `validateAgainstSystemHotKeys` | manual | `BlinkClipCore/ShortcutValidation.swift` |
| `f_1001ebf04` | `matchesSymbolicHotKey` | manual | `BlinkClipCore/ShortcutFunctions.swift` |
| `f_1001ec200` | `validateAgainstMenu` | manual | `BlinkClipCore/ShortcutValidation.swift` |
| `f_1001eca94` | `makeShortcutRecorder` | manual-review | `BlinkClipCore/ShortcutRecorderView.swift` |
| `f_1001ecbc4` | `recorderView` | manual-review | `BlinkClipCore/ShortcutRecorderView.swift` |
| `f_1001ed1c4` | `shortcutControlView` | manual-review | `BlinkClipCore/ShortcutControls.swift` |
| `f_1001ed830` | `presentationLabel` | manual-review | `BlinkClipCore/ShortcutControls.swift` |
| `f_1001eda4c` | `presentationText` | manual-review | `BlinkClipCore/ShortcutControls.swift` |
| `f_1001ee19c` | `setShortcut` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001ee308` | `okButton` | manual-review | `BlinkClipCore/ShortcutRecorderView.swift` |
| `f_1001ee478` | `clearValidationError` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001ee524` | `makeClearIcon` | manual-review | `BlinkClipCore/ShortcutControls.swift` |
| `f_1001ee604` | `styledLabel` | manual-review | `BlinkClipCore/ShortcutControls.swift` |
| `f_1001ee748` | `styledButtonLabel` | manual-review | `BlinkClipCore/ShortcutControls.swift` |
| `f_1001ef2bc` | `beginRecording` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001ef434` | `handleClearKey` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001ef60c` | `modifierSymbolsText` | manual-review | `BlinkClipCore/ShortcutControls.swift` |
| `f_1001eff84` | `startRecording` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f02d8` | `presentation` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f0460` | `currentState` | getter | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f04e8` | `currentValidationError` | getter | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f0558` | `hashInto` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f1150` | `updateState` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f12cc` | `optionKeyErrorMessage` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f132c` | `handleKeyEvent` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f1ab4` | `isEqual` | manual-review | `BlinkClipCore/ShortcutRecorder.swift` |
| `f_1001f1e64` | `shortcutValidatorService` | manual-review | `BlinkClipCore/ShortcutDependencies.swift` |
| `f_1001fdae8` | `updateLayout` | manual-review | `BlinkClip/UI/ImageCheckerboardView.swift` |
| `f_1001fe000` | `makeCheckerboardTile` | manual-review | `BlinkClip/UI/ImageCheckerboardView.swift` |
| `f_1001fe108` | `updateLayerColors` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_1001fe15c` | `foregroundColorSlot` | manual-review | `BlinkClipCore/SearchAppearance.swift` |
| `f_1001feab8` | `setupForegroundColor` | manual-review | `BlinkClipCore/SearchAppearance.swift` |
| `f_1001fec18` | `foregroundColor` | manual-review | `BlinkClipCore/SearchAppearance.swift` |
| `f_1001fef6c` | `setupBorderColor` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_1001ff0d0` | `borderColorSlot` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_1001ff49c` | `appearanceColor` | manual-review | `BlinkClipCore/SearchAppearance.swift` |
| `f_1001ff928` | `bodyFont` | manual-review | `BlinkClipCore/SearchAppearance.swift` |
| `f_1001ff964` | `preferredFont` | manual-review | `BlinkClipCore/SearchAppearance.swift` |
| `f_1001ffac0` | `hasNoForegroundColor` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_1001ffc58` | `dominantBackgroundColor` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_100200450` | `sortColorsByCount` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_100200560` | `addToCounts` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_1002006b0` | `addValueToCounts` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_1002067d4` | `isLightColor` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_100206b5c` | `hexString` | manual-review | `BlinkClip/UI/PreviewColorFormatting.swift` |
| `f_100206e50` | `resolvedAppearanceColor` | manual-review | `BlinkClipCore/SearchAppearance.swift` |
| `f_100206f30` | `colorForAppearance` | manual-review | `BlinkClipCore/SearchAppearance.swift` |
| `f_100207054` | `rotatedImage` | manual-review | `BlinkClip/UI/ReplicaImagePreviewContent.swift` |
| `f_1002072a0` | `toggleTrait` | manual-review | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_100207648` | `attributesApplyingTrait` | manual-review | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_100207b54` | `traitsAtSelection` | manual-review | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_100207db8` | `traitsFromAttributes` | manual | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_100208024` | `accumulateTraits` | manual | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_1002080e0` | `formUnion` | manual | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_100208290` | `contains` | single-call | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_1002083e4` | `setTraitInStorage` | manual-review | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_1002085e0` | `accumulateEnumeratedTraits` | manual | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_10020c714` | `currentApplication` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020c934` | `currentCalendar` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020cc48` | `currentBoard` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020cdd0` | `currentFile` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020cf40` | `currentUnrecognizedType` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020d3b0` | `currentLink` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020d434` | `currentDevices` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020d4f4` | `currentColor` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020d6a4` | `currentImage` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020d798` | `currentUnknown` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_10020d9c8` | `currentText` | getter | `BlinkClipCore/SearchFilterSymbols.swift` |
| `f_1002106d0` | `updateTraitButtons` | manual-review | `BlinkClip/UI/ReplicaPreviewAdapter.swift` |
| `f_1002127a4` | `makeSeparatorLabel` | manual-review | `BlinkClipCore/PreviewFooter.swift` |
| `f_100212840` | `constraintsForStack` | manual-review | `BlinkClipCore/PreviewFooter.swift` |
| `f_100212bac` | `childConstraints` | constraints | `BlinkClipCore/PreviewFooter.swift` |
| `f_100212ccc` | `previewAttributedString` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_100212e78` | `setEditorText` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_100213780` | `setupEditor` | manual-review | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_100213fe8` | `updateTraits` | manual-review | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_10021453c` | `scheduleStorageChangeDelivery` | manual-review | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_100214704` | `deliverStorageChange` | single-call | `BlinkClipCore/PreviewTextTraits.swift` |
| `f_100215cac` | `updateEditorText` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_100218b08` | `grayscaleColor` | manual-review | `BlinkClipCore/SelectionAppearance.swift` |
| `f_100219a90` | `setupBackgroundColor` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_100219bc4` | `backgroundColorSlot` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_100219ddc` | `fromEvent` | from-event | `BlinkClip/UI/NavigationKey.swift` |
| `f_100219df4` | `fromKeyCode` | from-keycode | `BlinkClip/UI/NavigationKey.swift` |
| `f_10021a0b0` | `showImageAnalysisOverlay` | manual-review | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_10021a8a8` | `imageOrientation` | manual-review | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_10021aabc` | `hideImageAnalysisOverlay` | manual-review | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_10021ad80` | `compactMenuItems` | manual-review | `BlinkClipCore/SearchMenu.swift` |
| `f_10021b124` | `isLayoutOrientationItem` | manual-review | `BlinkClipCore/SearchMenu.swift` |
| `f_10021b56c` | `cleanMenu` | manual-review | `BlinkClipCore/SearchMenu.swift` |
| `f_10021bf44` | `removeItemsInRange` | manual-review | `BlinkClipCore/SearchMenu.swift` |
| `f_10021c148` | `firstNonRetainedIndex` | manual-review | `BlinkClipCore/SearchMenu.swift` |
| `f_10021c304` | `compactRetainedItems` | manual-review | `BlinkClipCore/SearchMenu.swift` |
| `f_10021cadc` | `runAnimation` | manual-review | `BlinkClipCore/ViewAnimation.swift` |
| `f_10021ccd4` | `easeOutTimingFunction` | manual-review | `BlinkClipCore/ViewAnimation.swift` |
| `f_10021cd10` | `configureAnimationContext` | manual-review | `BlinkClipCore/ViewAnimation.swift` |
| `f_10021ce98` | `invokeCompletion` | manual-review | `BlinkClipCore/ViewAnimation.swift` |
| `f_10021cf38` | `easeInEaseOutTimingFunction` | manual-review | `BlinkClipCore/ViewAnimation.swift` |
| `f_10021d024` | `borderColor` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_10021d1cc` | `setBorderColor` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_10021d49c` | `setCornerRadius` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_10021d7a4` | `visualEffectView` | manual-review | `BlinkClipCore/PreviewWindows.swift` |
| `f_1002348a8` | `fromEvent` | from-event | `BlinkClip/UI/CollectionNavigation.swift` |
| `f_10023565c` | `currentStoredBackgroundColor` | getter | `BlinkClipCore/LayerBackedView.swift` |
| `f_1002356a8` | `setStoredBackgroundColor` | setter | `BlinkClipCore/LayerBackedView.swift` |
| `f_1002359f4` | `refreshAppearanceColors` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_100235f6c` | `updateForAppearanceChange` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_1002360c0` | `updateAppearance` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_100236188` | `updateLayerColors` | manual-review | `BlinkClipCore/LayerBackedView.swift` |
| `f_10023adf0` | `makeTextField` | lazy-factory | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023af6c` | `setTextColor` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023b1a4` | `currentTextOrNil` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023b214` | `updateText` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023b3e0` | `isEditable` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023b414` | `setEditable` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023b578` | `placeholderText` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023b600` | `setPlaceholder` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023b954` | `configureTextField` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023bfdc` | `abortEditing` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023c01c` | `resetText` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023c304` | `focus` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023c56c` | `notifyDidEndEditing` | manual-review | `BlinkClipCore/PreviewTitleLabel.swift` |
| `f_10023cc80` | `makeIconView` | lazy-factory | `BlinkClipCore/ToolbarButton.swift` |
| `f_10023ce40` | `updateIcon` | manual-review | `BlinkClipCore/ToolbarButton.swift` |
| `f_10023d784` | `updateLayerAppearance` | manual-review | `BlinkClipCore/ToolbarButton.swift` |
| `f_10023deb4` | `makeTitleLabelField` | lazy-factory | `BlinkClipCore/ToolbarButton.swift` |
| `f_10023e080` | `sizeConstraints` | manual-review | `BlinkClipCore/ToolbarButton.swift` |
| `f_10023f230` | `updateBackground` | manual-review | `BlinkClipCore/ToolbarButton.swift` |
| `f_10023fb74` | `stackViewConstraints` | manual-review | `BlinkClipCore/ToolbarButton.swift` |
| `f_100240838` | `makeImageView` | lazy-factory | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_1002408c0` | `makeContentView` | lazy-factory | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_10024095c` | `makeScrollView` | lazy-factory | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_100240a18` | `currentImage` | getter | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_100240a64` | `setImage` | setter | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_100240be8` | `setTextRecognitionEnabled` | setter | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_1002411cc` | `zoomToFit` | manual-review | `BlinkClip/UI/ImageTextSelection.swift` |
| `f_1002ca920` | `decodeOrDefault` | manual-review | `BlinkClipCore/ConfigurationFunctions.swift` |
| `f_1002cb458` | `decodeOldAndNew` | manual-review | `BlinkClipCore/ConfigurationFunctions.swift` |
| `f_1002cb804` | `castValue` | manual-review | `BlinkClipCore/ConfigurationFunctions.swift` |
| `f_1002cc5a8` | `castStoredValue` | manual-review | `BlinkClipCore/ConfigurationFunctions.swift` |
| `f_1002d4738` | `recognizeText` | manual-review | `BlinkClipCore/OCR.swift` |
| `f_1002d4830` | `performTextRecognition` | manual-review | `BlinkClipCore/OCR.swift` |
| `f_1002d4ba0` | `preparedImageData` | manual-review | `BlinkClipCore/OCR.swift` |
| `f_1002d576c` | `wordsFromObservations` | manual-review | `BlinkClipCore/OCR.swift` |
| `f_1002d7694` | `today` | manual | `BlinkClipCore/SearchDateRanges.swift` |
| `f_1002d7a14` | `yesterday` | manual | `BlinkClipCore/SearchDateRanges.swift` |
| `f_1002d7db8` | `thisWeek` | manual-review | `BlinkClipCore/SearchDateRanges.swift` |
| `f_1002d8300` | `lastWeek` | manual-review | `BlinkClipCore/SearchDateRanges.swift` |
| `f_1002d8860` | `last30Days` | manual | `BlinkClipCore/SearchDateRanges.swift` |
| `f_1002d8ce0` | `dateFilters` | manual-review | `BlinkClipCore/SearchDateRanges.swift` |
| `f_1002d8e9c` | `titleForFilterValue` | manual-review | `BlinkClipCore/SearchDateEncoding.swift` |
| `f_1002d9d2c` | `filterNodeForRange` | manual-review | `BlinkClipCore/SearchDateEncoding.swift` |
| `f_1002da16c` | `deduplicatedFilters` | manual-review | `BlinkClipCore/SearchQueryNormalization.swift` |
| `f_1002dc9b8` | `listNameForSuggestion` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002dcca4` | `nodesApplyingSuggestion` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002ddc10` | `listNameForKind` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002ddcf0` | `allNodesEmpty` | manual-review | `BlinkClipCore/SearchQuery.swift` |
| `f_1002df190` | `contextSuggestions` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002e00a0` | `filterGroups` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002f3d94` | `normalizedFilterValue` | manual-review | `BlinkClipCore/SearchQuery.swift` |
| `f_1002f45b0` | `predicateString` | manual-review | `BlinkClipCore/SearchQuery.swift` |
| `f_1002f5100` | `fuzzyPattern` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002f51d0` | `splitOnWhitespace` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002f5588` | `wordPatterns` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002f5748` | `matchRanges` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1002f5a50` | `makeViewProvider` | manual-review | `BlinkClipCore/SearchFilterView.swift` |
| `f_1002f5c94` | `loadAttachmentView` | manual-review | `BlinkClipCore/SearchFilterView.swift` |
| `f_1002f5d4c` | `setupAttachmentView` | manual-review | `BlinkClipCore/SearchFilterView.swift` |
| `f_1002f5d74` | `attachmentViewFrame` | manual-review | `BlinkClipCore/SearchFilterView.swift` |
| `f_1002f5e18` | `appendSnapshot` | verb-call | `BlinkClipCore/SearchInputHistory.swift` |
| `f_1002f5fe8` | `flushPendingSnapshot` | manual-review | `BlinkClipCore/SearchInputHistory.swift` |
| `f_1002f60fc` | `schedulePendingFlush` | manual-review | `BlinkClipCore/SearchInputHistory.swift` |
| `f_1002f61f0` | `undoSnapshot` | manual-review | `BlinkClipCore/SearchInputHistory.swift` |
| `f_1002f63b8` | `redoSnapshot` | manual-review | `BlinkClipCore/SearchInputHistory.swift` |
| `f_1002f6550` | `clearHistory` | manual-review | `BlinkClipCore/SearchInputHistory.swift` |
| `f_1002f78f8` | `contextForCaret` | manual-review | `BlinkClipCore/SearchInputContext.swift` |
| `f_1002f8760` | `appendBufferAsNodes` | manual-review | `BlinkClipCore/SearchTextTokens.swift` |
| `f_1002fad30` | `undoManager` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_1002fd5e4` | `makeUndoManager` | factory | `BlinkClipCore/Pasteboard.swift` |
| `f_1002fe514` | `startFileLogging` | manual-review | `BlinkClipCore/DiagnosticsManager.swift` |
| `f_1002fe72c` | `setDiagnosticsEnabled` | manual-review | `BlinkClipCore/DiagnosticsManager.swift` |
| `f_1002feb60` | `currentFileURL` | getter | `BlinkClipCore/DiagnosticsManager.swift` |
| `f_1002febd4` | `logFileURLs` | manual-review | `BlinkClipCore/DiagnosticsManager.swift` |
| `f_1002fef28` | `captureDiagnosticsFile` | manual-review | `BlinkClipCore/DiagnosticsHistory.swift` |
| `f_1002ff9c8` | `withResult` | single-call | `BlinkClipCore/ObjCExceptionBridge.swift` |
| `f_1002ffc68` | `withResult` | single-call | `BlinkClipCore/ObjCExceptionBridge.swift` |
| `f_100308a6c` | `hasTransparency` | manual-review | `BlinkClipCore/ImagePreviewMetadata.swift` |
| `f_100308f88` | `titleOrDefault` | manual-review | `BlinkClipCore/PreviewTitles.swift` |
| `f_100309008` | `itemTypeTitle` | manual-review | `BlinkClipCore/PreviewTitles.swift` |
| `f_1003095bc` | `isPlainText` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_100309700` | `fullRange` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_100309720` | `markIfAttributed` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1003097c0` | `attributedStringWithNormalizedParagraphs` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_100309924` | `applyParagraphStyle` | manual | `BlinkClipCore/PasteboardItem.swift` |
| `f_100309c40` | `makeRelativeFormatter` | manual-review | `BlinkClipCore/DateDisplay.swift` |
| `f_100309c7c` | `makeComponentsFormatter` | manual-review | `BlinkClipCore/DateDisplay.swift` |
| `f_100309cd0` | `makeAbsoluteFormatter` | manual-review | `BlinkClipCore/DateDisplay.swift` |
| `f_100309d18` | `largestUnit` | manual-review | `BlinkClipCore/DateDisplay.swift` |
| `f_100309e0c` | `formattedDateString` | manual-review | `BlinkClipCore/DateDisplay.swift` |
| `f_10030f3e0` | `itemTypeNames` | manual-review | `BlinkClipCore/SearchSuggestions.swift` |
| `f_10030f5c8` | `compressedData` | manual-review | `BlinkClipCore/PasteboardDataCodec.swift` |
| `f_10030f6e8` | `decompressedData` | manual-review | `BlinkClipCore/PasteboardDataCodec.swift` |
| `f_10030f920` | `decodeBuffer` | manual-review | `BlinkClipCore/PasteboardDataCodec.swift` |
| `f_100311f7c` | `overrideColor` | manual-review | `BlinkClipCore/SourceApplicationColors.swift` |
| `f_100312874` | `quickLookThumbnailData` | manual-review | `BlinkClipCore/FilePreviewMetadata.swift` |
| `f_100313548` | `previewMetadata` | manual-review | `BlinkClipCore/ImagePreviewMetadata.swift` |
| `f_1003195f4` | `hasPrefix` | manual-review | `BlinkClipCore/PasteboardDataCodec.swift` |
| `f_10031a870` | `firstByte` | manual-review | `BlinkClipCore/PasteboardDataCodec.swift` |
| `f_10031a8e8` | `encodeItems` | verb-call | `BlinkClipCore/PasteboardDataCodec.swift` |
| `f_10031aeec` | `decodeItems` | manual-review | `BlinkClipCore/PasteboardDataCodec.swift` |
| `f_10031bcdc` | `textOnlyItems` | manual-review | `BlinkClipCore/PasteboardRestore.swift` |
| `f_1003202f0` | `shareableItems` | manual-review | `BlinkClipCore/PreviewSharing.swift` |
| `f_100320cc0` | `hasShareableItems` | manual-review | `BlinkClipCore/PreviewSharing.swift` |
| `f_1003216bc` | `checksumForItems` | manual-review | `BlinkClipCore/PasteboardChecksums.swift` |
| `f_100321f48` | `isHexColor` | manual-review | `BlinkClipCore/PasteboardClassification.swift` |
| `f_100322ae4` | `archivedItemsChecksum` | manual-review | `BlinkClipCore/PasteboardChecksums.swift` |
| `f_100322d94` | `checksumForString` | manual-review | `BlinkClipCore/PasteboardChecksums.swift` |
| `f_100322fe4` | `hexStrings` | manual-review | `BlinkClipCore/PasteboardChecksums.swift` |
| `f_100323324` | `updateHasher` | manual-review | `BlinkClipCore/PasteboardChecksums.swift` |
| `f_10032362c` | `classifyItems` | manual-review | `BlinkClipCore/PasteboardClassification.swift` |
| `f_1003245fc` | `valueFromAttributes` | manual-review | `BlinkClipCore/PinboardAttributes.swift` |
| `f_10035ca9c` | `saveContext` | manual-review | `BlinkClipCore/ContextUndo.swift` |
| `f_10035e4d8` | `performContextSave` | manual-review | `BlinkClipCore/ContextUndo.swift` |
| `f_100378664` | `makePasteboardCaptureState` | manual-review | `BlinkClipCore/PasteboardCaptureState.swift` |
| `f_10037875c` | `writeItems` | manual | `BlinkClipCore/PasteboardItem.swift` |
| `f_100378ac0` | `startMonitoring` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_100378bc8` | `stopMonitoring` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037a028` | `pollForChanges` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037aaf4` | `syncCount` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037ad14` | `stopMonitoringWithNotification` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037ad40` | `startMonitoringWithNotification` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037ad4c` | `performAndPostStatusChange` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037ae9c` | `createItems` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037b034` | `createItem` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037b278` | `setsEqual` | manual-review | `BlinkClipCore/PasteboardPolicies.swift` |
| `f_10037b428` | `persistCaptureState` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037ba14` | `shouldCaptureChange` | manual-review | `BlinkClipCore/PasteboardPolicies.swift` |
| `f_10037c22c` | `shouldCaptureType` | manual-review | `BlinkClipCore/PasteboardPolicies.swift` |
| `f_10037c4a4` | `resolvedUndoManager` | manual-review | `BlinkClipCore/Pasteboard.swift` |
| `f_10037c4a8` | `setString` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037c6d4` | `itemWithString` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037c7bc` | `itemWithURL` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037c9a8` | `plainTextString` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037cc6c` | `fileURL` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037cd68` | `image` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037ce0c` | `url` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037d210` | `urlName` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037d33c` | `attributedString` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037d5c4` | `imageData` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037d810` | `dataForType` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037d8c8` | `setData` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037da6c` | `currentOrderedTypes` | getter | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037dab0` | `removeData` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037df78` | `encodeToEncoder` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037e4b8` | `stringForType` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037e5e0` | `nsDataForType` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037e6b0` | `setValue` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037ebdc` | `attributedStringForTypes` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037f314` | `isSecureCodingSupported` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_10037f520` | `decodeWithCoder` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_100381fdc` | `rtfData` | manual-review | `BlinkClipCore/PasteboardRestore.swift` |
| `f_10038222c` | `itemsFromSelections` | manual-review | `BlinkClipCore/PasteboardRestore.swift` |
| `f_100383574` | `removeTypesMatching` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_1003838bc` | `addBlinkClipMarker` | manual-review | `BlinkClipCore/PasteboardItem.swift` |
| `f_100383a0c` | `joinedAttributedString` | manual-review | `BlinkClipCore/PasteboardRestore.swift` |
| `f_100383df4` | `restoreImageItems` | manual | `BlinkClipCore/PasteboardImageRestore.swift` |
| `f_100384824` | `temporaryDirectoryURL` | manual-review | `BlinkClipCore/PasteboardImageRestore.swift` |
| `f_100384aac` | `scheduleTemporaryCleanup` | manual-review | `BlinkClipCore/PasteboardImageRestore.swift` |
| `f_100384e6c` | `removeExpiredFiles` | manual-review | `BlinkClipCore/PasteboardImageRestore.swift` |
| `f_1003b80f0` | `listContext` | manual-review | `BlinkClipCore/CollectionListContext.swift` |
| `f_1003bae08` | `updateTitle` | manual-review | `BlinkClipCore/PreviewTitles.swift` |
| `f_1003bc874` | `revealItemsInFinder` | manual-review | `BlinkClipCore/FilePreviewActions.swift` |
| `f_1003c0be0` | `hasDifferentText` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1003c14d0` | `attributesForSubmission` | manual-review | `BlinkClipCore/TextPreviewSubmission.swift` |
| `f_1003c1860` | `copyFontTraits` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1003c7c4c` | `scaledImage` | manual-review | `BlinkClipCore/SourceApplicationImageColor.swift` |
| `f_1003c7f84` | `adjustedColor` | manual-review | `BlinkClipCore/SourceApplicationImageColor.swift` |
| `f_1003c89c8` | `pngData` | manual-review | `BlinkClipCore/PasteboardImageEncoding.swift` |
| `f_1003c8b58` | `jpegData` | manual-review | `BlinkClipCore/ImagePreviewMetadata.swift` |
| `f_1003c9f3c` | `aspectFittedImage` | manual-review | `BlinkClipCore/ImagePreviewMetadata.swift` |
| `f_1003ca024` | `resizedImage` | manual-review | `BlinkClipCore/ImagePreviewMetadata.swift` |
| `f_1003d1cc0` | `makeTextField` | lazy-factory | `BlinkClipCore/ItemTitleLabel.swift` |
| `f_1003d1dbc` | `commitEditing` | manual-review | `BlinkClipCore/ItemTitleLabel.swift` |
| `f_1003d2488` | `beginEditing` | manual-review | `BlinkClipCore/ItemTitleLabel.swift` |
| `f_1003d2838` | `cancelEditing` | manual-review | `BlinkClipCore/ItemTitleLabel.swift` |
| `f_1003df0b0` | `setContentView` | manual-review | `BlinkClipCore/PreviewFooter.swift` |
| `f_1003df260` | `viewConstraints` | constraints | `BlinkClipCore/PreviewFooter.swift` |
| `f_1003e0820` | `metadataConstraints` | constraints | `BlinkClip/UI/ReplicaColorPreviewContent.swift` |
| `f_1003e2f54` | `makeMultipleFilesView` | lazy-factory | `BlinkClip/UI/ReplicaFilePreviewContent.swift` |
| `f_1003e57b8` | `checkerboardConstraints` | constraints | `BlinkClip/UI/ReplicaImagePreviewContent.swift` |
| `f_1003eb330` | `displayedText` | manual-review | `BlinkClipCore/PreviewAttributedText.swift` |
| `f_1003eb4a8` | `applyPreviewTextColors` | manual-review | `BlinkClipCore/PreviewTextColors.swift` |
| `f_1003ebcd4` | `applyPreviewTextColors` | manual-review | `BlinkClip/UI/ReplicaPreviewAdapter.swift` |
| `f_100ae5e74` | `AXIsProcessTrusted` | single-call | `BlinkClipCore/AccessibilityService.swift` |
| `f_100ae5e90` | `trustedStatusPublisher` | manual-review | `BlinkClipCore/AccessibilityService.swift` |
| `f_100ae641c` | `postPasteKeystroke` | manual-review | `BlinkClipCore/PasteKeyTranslation.swift` |
| `f_100ae6428` | `sendCommandKeyEvent` | manual-review | `BlinkClipCore/PasteKeyTranslation.swift` |
| `f_100ae6678` | `layoutCharacter` | manual-review | `BlinkClipCore/PasteKeyTranslation.swift` |

## 2. File renames (detected by `git diff -M` vs HEAD)

| Old path | New path |
|---|---|
| `replica/Assets/SnapclipAppIcon.icns` | `replica/Assets/BlinkClipAppIcon.icns` |
| `replica/Assets/SnapclipIcon.png` | `replica/Assets/BlinkClipIcon.png` |
| `replica/Sources/Snapclip/AppIntents/PastoCreateItemIntent.swift` | `replica/Sources/BlinkClip/AppIntents/BlinkClipCreateItemIntent.swift` |
| `replica/Sources/Snapclip/AppIntents/PastoGetItemAtIndexIntent.swift` | `replica/Sources/BlinkClip/AppIntents/BlinkClipGetItemAtIndexIntent.swift` |
| `replica/Sources/Snapclip/AppIntents/PastoGetLatestItemIntent.swift` | `replica/Sources/BlinkClip/AppIntents/BlinkClipGetLatestItemIntent.swift` |
| `replica/Sources/Snapclip/AppIntents/PastoPinboardAppIntents.swift` | `replica/Sources/BlinkClip/AppIntents/BlinkClipPinboardAppIntents.swift` |
| `replica/Sources/Snapclip/AppIntents/PastoShortcutsProvider.swift` | `replica/Sources/BlinkClip/AppIntents/BlinkClipShortcutsProvider.swift` |
| `replica/Sources/Snapclip/AppMain.swift` | `replica/Sources/BlinkClip/AppMain.swift` |
| `replica/Sources/Snapclip/BackgroundService.swift` | `replica/Sources/BlinkClip/BackgroundService.swift` |
| `replica/Sources/Snapclip/GlobalHotKey.swift` | `replica/Sources/BlinkClip/GlobalHotKey.swift` |
| `replica/Sources/Snapclip/ICloudDriveSyncController.swift` | `replica/Sources/BlinkClip/ICloudDriveSyncController.swift` |
| `replica/Sources/Snapclip/Screenshot/ScreenshotCoordinator.swift` | `replica/Sources/BlinkClip/Screenshot/ScreenshotCoordinator.swift` |
| `replica/Sources/Snapclip/Screenshot/ScreenshotFocusRestorer.swift` | `replica/Sources/BlinkClip/Screenshot/ScreenshotFocusRestorer.swift` |
| `replica/Sources/Snapclip/Screenshot/ScreenshotHistoryBridge.swift` | `replica/Sources/BlinkClip/Screenshot/ScreenshotHistoryBridge.swift` |
| `replica/Sources/Snapclip/Screenshot/ScreenshotWindowHider.swift` | `replica/Sources/BlinkClip/Screenshot/ScreenshotWindowHider.swift` |
| `replica/Sources/Snapclip/SourceAppColor.swift` | `replica/Sources/BlinkClip/SourceAppColor.swift` |
| `replica/Sources/Snapclip/UI/OriginalAccessibilityModals.swift` | `replica/Sources/BlinkClip/UI/AccessibilityModals.swift` |
| `replica/Sources/Snapclip/UI/OriginalAccessibilityRequestAction.swift` | `replica/Sources/BlinkClip/UI/AccessibilityRequestAction.swift` |
| `replica/Sources/Snapclip/UI/OriginalAdaptiveScalingImageView.swift` | `replica/Sources/BlinkClip/UI/AdaptiveScalingImageView.swift` |
| `replica/Sources/Snapclip/UI/AuxiliaryViews.swift` | `replica/Sources/BlinkClip/UI/AuxiliaryViews.swift` |
| `replica/Sources/Snapclip/UI/PastoAboutWindowController.swift` | `replica/Sources/BlinkClip/UI/BlinkClipAboutWindowController.swift` |
| `replica/Sources/Snapclip/UI/PastoInAppUpdater.swift` | `replica/Sources/BlinkClip/UI/BlinkClipInAppUpdater.swift` |
| `replica/Sources/Snapclip/UI/OriginalCardShortcutIndicator.swift` | `replica/Sources/BlinkClip/UI/CardShortcutIndicator.swift` |
| `replica/Sources/Snapclip/UI/CardSourceIconPresentation.swift` | `replica/Sources/BlinkClip/UI/CardSourceIconPresentation.swift` |
| `replica/Sources/Snapclip/UI/CloudKitSyncController.swift` | `replica/Sources/BlinkClip/UI/CloudKitSyncController.swift` |
| `replica/Sources/Snapclip/UI/OriginalCollectionNavigation.swift` | `replica/Sources/BlinkClip/UI/CollectionNavigation.swift` |
| `replica/Sources/Snapclip/UI/OriginalCollectionScrollAnimator.swift` | `replica/Sources/BlinkClip/UI/CollectionScrollAnimator.swift` |
| `replica/Sources/Snapclip/UI/OriginalCompactTextContent.swift` | `replica/Sources/BlinkClip/UI/CompactTextContent.swift` |
| `replica/Sources/Snapclip/UI/OriginalCompactTextFooter.swift` | `replica/Sources/BlinkClip/UI/CompactTextFooter.swift` |
| `replica/Sources/Snapclip/UI/FilterBrowser.swift` | `replica/Sources/BlinkClip/UI/FilterBrowser.swift` |
| `replica/Sources/Snapclip/UI/OriginalHeadTruncatedLabel.swift` | `replica/Sources/BlinkClip/UI/HeadTruncatedLabel.swift` |
| `replica/Sources/Snapclip/UI/OriginalHistoryCapacityControl.swift` | `replica/Sources/BlinkClip/UI/HistoryCapacityControl.swift` |
| `replica/Sources/Snapclip/UI/HistoryRetentionCopy.swift` | `replica/Sources/BlinkClip/UI/HistoryRetentionCopy.swift` |
| `replica/Sources/Snapclip/UI/HistoryRetentionSaving.swift` | `replica/Sources/BlinkClip/UI/HistoryRetentionSaving.swift` |
| `replica/Sources/Snapclip/UI/OriginalImageCheckerboardView.swift` | `replica/Sources/BlinkClip/UI/ImageCheckerboardView.swift` |
| `replica/Sources/Snapclip/UI/OriginalImageSizeBadge.swift` | `replica/Sources/BlinkClip/UI/ImageSizeBadge.swift` |
| `replica/Sources/Snapclip/UI/OriginalImageTextSelection.swift` | `replica/Sources/BlinkClip/UI/ImageTextSelection.swift` |
| `replica/Sources/Snapclip/UI/OriginalLinkPreviewViewport.swift` | `replica/Sources/BlinkClip/UI/LinkPreviewViewport.swift` |
| `replica/Sources/Snapclip/UI/OriginalNavigationKey.swift` | `replica/Sources/BlinkClip/UI/NavigationKey.swift` |
| `replica/Sources/Snapclip/UI/OriginalPanelTabBar.swift` | `replica/Sources/BlinkClip/UI/PanelTabBar.swift` |
| `replica/Sources/Snapclip/UI/OriginalPanelToolbar.swift` | `replica/Sources/BlinkClip/UI/PanelToolbar.swift` |
| `replica/Sources/Snapclip/UI/PanelViews.swift` | `replica/Sources/BlinkClip/UI/PanelViews.swift` |
| `replica/Sources/Snapclip/UI/PermissionStatusProbe.swift` | `replica/Sources/BlinkClip/UI/PermissionStatusProbe.swift` |
| `replica/Sources/Snapclip/UI/PermissionStatusView.swift` | `replica/Sources/BlinkClip/UI/PermissionStatusView.swift` |
| `replica/Sources/Snapclip/UI/OriginalPinboardHeaderIcon.swift` | `replica/Sources/BlinkClip/UI/PinboardHeaderIcon.swift` |
| `replica/Sources/Snapclip/UI/OriginalPinboardTabTitle.swift` | `replica/Sources/BlinkClip/UI/PinboardTabTitle.swift` |
| `replica/Sources/Snapclip/UI/PreviewAnchor.swift` | `replica/Sources/BlinkClip/UI/PreviewAnchor.swift` |
| `replica/Sources/Snapclip/UI/OriginalPreviewColorFormatting.swift` | `replica/Sources/BlinkClip/UI/PreviewColorFormatting.swift` |
| `replica/Sources/Snapclip/UI/ReplicaBrand.swift` | `replica/Sources/BlinkClip/UI/ReplicaBrand.swift` |
| `replica/Sources/Snapclip/UI/ReplicaCanonicalCardContent.swift` | `replica/Sources/BlinkClip/UI/ReplicaCanonicalCardContent.swift` |
| `replica/Sources/Snapclip/UI/ReplicaCardContextSelection.swift` | `replica/Sources/BlinkClip/UI/ReplicaCardContextSelection.swift` |
| `replica/Sources/Snapclip/UI/ReplicaCardTitle.swift` | `replica/Sources/BlinkClip/UI/ReplicaCardTitle.swift` |
| `replica/Sources/Snapclip/UI/ReplicaColorPreviewContent.swift` | `replica/Sources/BlinkClip/UI/ReplicaColorPreviewContent.swift` |
| `replica/Sources/Snapclip/UI/ReplicaCopiedOSD.swift` | `replica/Sources/BlinkClip/UI/ReplicaCopiedOSD.swift` |
| `replica/Sources/Snapclip/UI/ReplicaFileCardImage.swift` | `replica/Sources/BlinkClip/UI/ReplicaFileCardImage.swift` |
| `replica/Sources/Snapclip/UI/ReplicaFilePreviewContent.swift` | `replica/Sources/BlinkClip/UI/ReplicaFilePreviewContent.swift` |
| `replica/Sources/Snapclip/UI/ReplicaImagePreviewContent.swift` | `replica/Sources/BlinkClip/UI/ReplicaImagePreviewContent.swift` |
| `replica/Sources/Snapclip/UI/ReplicaLinkMetadataContent.swift` | `replica/Sources/BlinkClip/UI/ReplicaLinkMetadataContent.swift` |
| `replica/Sources/Snapclip/UI/ReplicaLinkPreviewContent.swift` | `replica/Sources/BlinkClip/UI/ReplicaLinkPreviewContent.swift` |
| `replica/Sources/Snapclip/UI/ReplicaNativeCardCollection.swift` | `replica/Sources/BlinkClip/UI/ReplicaNativeCardCollection.swift` |
| `replica/Sources/Snapclip/UI/ReplicaNativeDragPreview.swift` | `replica/Sources/BlinkClip/UI/ReplicaNativeDragPreview.swift` |
| `replica/Sources/Snapclip/UI/ReplicaPanelContentView.swift` | `replica/Sources/BlinkClip/UI/ReplicaPanelContentView.swift` |
| `replica/Sources/Snapclip/UI/ReplicaPanelGlassBackground.swift` | `replica/Sources/BlinkClip/UI/ReplicaPanelGlassBackground.swift` |
| `replica/Sources/Snapclip/UI/ReplicaPanelResizeHandle.swift` | `replica/Sources/BlinkClip/UI/ReplicaPanelResizeHandle.swift` |
| `replica/Sources/Snapclip/UI/OriginalReplicaPreviewAdapter.swift` | `replica/Sources/BlinkClip/UI/ReplicaPreviewAdapter.swift` |
| `replica/Sources/Snapclip/UI/ReplicaReadOnlyPreviewContent.swift` | `replica/Sources/BlinkClip/UI/ReplicaReadOnlyPreviewContent.swift` |
| `replica/Sources/Snapclip/UI/ReplicaSearchIndex.swift` | `replica/Sources/BlinkClip/UI/ReplicaSearchIndex.swift` |
| `replica/Sources/Snapclip/UI/ReplicaSearchSuggestionSource.swift` | `replica/Sources/BlinkClip/UI/ReplicaSearchSuggestionSource.swift` |
| `replica/Sources/Snapclip/UI/ReplicaSearchSuggestionsMenu.swift` | `replica/Sources/BlinkClip/UI/ReplicaSearchSuggestionsMenu.swift` |
| `replica/Sources/Snapclip/UI/ReplicaUIController.swift` | `replica/Sources/BlinkClip/UI/ReplicaUIController.swift` |
| `replica/Sources/Snapclip/UI/RichTextEditor.swift` | `replica/Sources/BlinkClip/UI/RichTextEditor.swift` |
| `replica/Sources/Snapclip/UI/ScreenshotSettingsCopy.swift` | `replica/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift` |
| `replica/Sources/Snapclip/UI/SearchEditor.swift` | `replica/Sources/BlinkClip/UI/SearchEditor.swift` |
| `replica/Sources/Snapclip/UI/SettingsCopy.swift` | `replica/Sources/BlinkClip/UI/SettingsCopy.swift` |
| `replica/Sources/Snapclip/UI/SettingsShortcutReset.swift` | `replica/Sources/BlinkClip/UI/SettingsShortcutReset.swift` |
| `replica/Sources/Snapclip/UI/SettingsShortcutRowRestore.swift` | `replica/Sources/BlinkClip/UI/SettingsShortcutRowRestore.swift` |
| `replica/Sources/Snapclip/UI/OriginalSettingsSplitView.swift` | `replica/Sources/BlinkClip/UI/SettingsSplitView.swift` |
| `replica/Sources/Snapclip/UI/ShortcutRecorder.swift` | `replica/Sources/BlinkClip/UI/ShortcutRecorder.swift` |
| `replica/Sources/Snapclip/UI/OriginalStackSnippetCell.swift` | `replica/Sources/BlinkClip/UI/StackSnippetCell.swift` |
| `replica/Sources/Snapclip/UI/OriginalStackSnippetText.swift` | `replica/Sources/BlinkClip/UI/StackSnippetText.swift` |
| `replica/Sources/Snapclip/UI/OriginalSuggestionAttributedTitle.swift` | `replica/Sources/BlinkClip/UI/SuggestionAttributedTitle.swift` |
| `replica/Sources/Snapclip/UI/OriginalUnavailableCompactContent.swift` | `replica/Sources/BlinkClip/UI/UnavailableCompactContent.swift` |
| `replica/Sources/Snapclip/UI/OriginalUnavailablePreviewContent.swift` | `replica/Sources/BlinkClip/UI/UnavailablePreviewContent.swift` |
| `replica/Sources/Snapclip/UI/WindowAppearancePreferenceObservation.swift` | `replica/Sources/BlinkClip/UI/WindowAppearancePreferenceObservation.swift` |
| `replica/Sources/Snapclip/WindowSharingPolicy.swift` | `replica/Sources/BlinkClip/WindowSharingPolicy.swift` |
| `replica/Sources/SnapclipCore/OriginalAccessibilityService.swift` | `replica/Sources/BlinkClipCore/AccessibilityService.swift` |
| `replica/Sources/SnapclipCore/AppBrand.swift` | `replica/Sources/BlinkClipCore/AppBrand.swift` |
| `replica/Sources/SnapclipCore/SnapclipAssetRenderer.swift` | `replica/Sources/BlinkClipCore/BlinkClipAssetRenderer.swift` |
| `replica/Sources/SnapclipCore/PastoCloudKitConfiguration.swift` | `replica/Sources/BlinkClipCore/BlinkClipCloudKitConfiguration.swift` |
| `replica/Sources/SnapclipCore/SnapclipResources/GeneratedIllustrations/SnapclipCopyToClipboard@2x.png` | `replica/Sources/BlinkClipCore/BlinkClipResources/GeneratedIllustrations/BlinkClipCopyToClipboard@2x.png` |
| `replica/Sources/SnapclipCore/SnapclipResources/GeneratedIllustrations/SnapclipDirectPaste@2x.png` | `replica/Sources/BlinkClipCore/BlinkClipResources/GeneratedIllustrations/BlinkClipDirectPaste@2x.png` |
| `replica/Sources/SnapclipCore/SnapclipResources/GeneratedIllustrations/SnapclipPermissions@2x.png` | `replica/Sources/BlinkClipCore/BlinkClipResources/GeneratedIllustrations/BlinkClipPermissions@2x.png` |
| `replica/Sources/SnapclipCore/SnapclipResources/en.lproj/Localizable.strings` | `replica/Sources/BlinkClipCore/BlinkClipResources/en.lproj/Localizable.strings` |
| `replica/Sources/SnapclipCore/Resources/en.lproj/Localizable.stringsdict` | `replica/Sources/BlinkClipCore/BlinkClipResources/en.lproj/Localizable.stringsdict` |
| `replica/Sources/SnapclipCore/SnapclipResources/zh-Hans.lproj/Localizable.strings` | `replica/Sources/BlinkClipCore/BlinkClipResources/zh-Hans.lproj/Localizable.strings` |
| `replica/Sources/SnapclipCore/SnapclipResources/zh-Hans.lproj/Localizable.stringsdict` | `replica/Sources/BlinkClipCore/BlinkClipResources/zh-Hans.lproj/Localizable.stringsdict` |
| `replica/Sources/SnapclipCore/PastoUpdateChecker.swift` | `replica/Sources/BlinkClipCore/BlinkClipUpdateChecker.swift` |
| `replica/Sources/SnapclipCore/OriginalCardPresentation.swift` | `replica/Sources/BlinkClipCore/CardPresentation.swift` |
| `replica/Sources/SnapclipCore/ClipboardCollectionEntry.swift` | `replica/Sources/BlinkClipCore/ClipboardCollectionEntry.swift` |
| `replica/Sources/SnapclipCore/ClipboardCollectionItemReference.swift` | `replica/Sources/BlinkClipCore/ClipboardCollectionItemReference.swift` |
| `replica/Sources/SnapclipCore/ClipboardItemDataPersistence.swift` | `replica/Sources/BlinkClipCore/ClipboardItemDataPersistence.swift` |
| `replica/Sources/SnapclipCore/ClipboardItemObservation.swift` | `replica/Sources/BlinkClipCore/ClipboardItemObservation.swift` |
| `replica/Sources/SnapclipCore/ClipboardItemOrderPersistence.swift` | `replica/Sources/BlinkClipCore/ClipboardItemOrderPersistence.swift` |
| `replica/Sources/SnapclipCore/ClipboardItemTitlePersistence.swift` | `replica/Sources/BlinkClipCore/ClipboardItemTitlePersistence.swift` |
| `replica/Sources/SnapclipCore/ClipboardListAttributesObservation.swift` | `replica/Sources/BlinkClipCore/ClipboardListAttributesObservation.swift` |
| `replica/Sources/SnapclipCore/ClipboardListPersistence.swift` | `replica/Sources/BlinkClipCore/ClipboardListPersistence.swift` |
| `replica/Sources/SnapclipCore/ClipboardPersistence.swift` | `replica/Sources/BlinkClipCore/ClipboardPersistence.swift` |
| `replica/Sources/SnapclipCore/ClipboardRestoreItem.swift` | `replica/Sources/BlinkClipCore/ClipboardRestoreItem.swift` |
| `replica/Sources/SnapclipCore/ClipboardSearchCollection.swift` | `replica/Sources/BlinkClipCore/ClipboardSearchCollection.swift` |
| `replica/Sources/SnapclipCore/ClipboardSearchRecord.swift` | `replica/Sources/BlinkClipCore/ClipboardSearchRecord.swift` |
| `replica/Sources/SnapclipCore/ClipboardSnapshotReader.swift` | `replica/Sources/BlinkClipCore/ClipboardSnapshotReader.swift` |
| `replica/Sources/SnapclipCore/ClipboardSourcePersistence.swift` | `replica/Sources/BlinkClipCore/ClipboardSourcePersistence.swift` |
| `replica/Sources/SnapclipCore/ClipboardStore.swift` | `replica/Sources/BlinkClipCore/ClipboardStore.swift` |
| `replica/Sources/SnapclipCore/OriginalCloudKitContracts.swift` | `replica/Sources/BlinkClipCore/CloudKitContracts.swift` |
| `replica/Sources/SnapclipCore/OriginalCloudKitGraph.swift` | `replica/Sources/BlinkClipCore/CloudKitGraph.swift` |
| `replica/Sources/SnapclipCore/OriginalCloudKitJournal.swift` | `replica/Sources/BlinkClipCore/CloudKitJournal.swift` |
| `replica/Sources/SnapclipCore/OriginalCloudKitSyncEngine.swift` | `replica/Sources/BlinkClipCore/CloudKitSyncEngine.swift` |
| `replica/Sources/SnapclipCore/OriginalCollectionListContext.swift` | `replica/Sources/BlinkClipCore/CollectionListContext.swift` |
| `replica/Sources/SnapclipCore/OriginalCollectionShortcutActions.swift` | `replica/Sources/BlinkClipCore/CollectionShortcutActions.swift` |
| `replica/Sources/SnapclipCore/OriginalCollectionSnapshot.swift` | `replica/Sources/BlinkClipCore/CollectionSnapshot.swift` |
| `replica/Sources/SnapclipCore/OriginalColorPreviewMetadata.swift` | `replica/Sources/BlinkClipCore/ColorPreviewMetadata.swift` |
| `replica/Sources/SnapclipCore/OriginalConfigurationFunctions.swift` | `replica/Sources/BlinkClipCore/ConfigurationFunctions.swift` |
| `replica/Sources/SnapclipCore/OriginalContextUndo.swift` | `replica/Sources/BlinkClipCore/ContextUndo.swift` |
| `replica/Sources/SnapclipCore/OriginalDateDisplay.swift` | `replica/Sources/BlinkClipCore/DateDisplay.swift` |
| `replica/Sources/SnapclipCore/OriginalDependencies.swift` | `replica/Sources/BlinkClipCore/Dependencies.swift` |
| `replica/Sources/SnapclipCore/OriginalDiagnosticDispatcher.swift` | `replica/Sources/BlinkClipCore/DiagnosticDispatcher.swift` |
| `replica/Sources/SnapclipCore/OriginalDiagnosticsAppActions.swift` | `replica/Sources/BlinkClipCore/DiagnosticsAppActions.swift` |
| `replica/Sources/SnapclipCore/OriginalDiagnosticsHistory.swift` | `replica/Sources/BlinkClipCore/DiagnosticsHistory.swift` |
| `replica/Sources/SnapclipCore/OriginalDiagnosticsManager.swift` | `replica/Sources/BlinkClipCore/DiagnosticsManager.swift` |
| `replica/Sources/SnapclipCore/OriginalFilePreviewMetadata.swift` | `replica/Sources/BlinkClipCore/FilePreviewMetadata.swift` |
| `replica/Sources/SnapclipCore/OriginalFilterBrowserPopover.swift` | `replica/Sources/BlinkClipCore/FilterBrowserPopover.swift` |
| `replica/Sources/SnapclipCore/OriginalGlobalShortcutMonitor.swift` | `replica/Sources/BlinkClipCore/GlobalShortcutMonitor.swift` |
| `replica/Sources/SnapclipCore/OriginalHistoryCapacity.swift` | `replica/Sources/BlinkClipCore/HistoryCapacity.swift` |
| `replica/Sources/SnapclipCore/ICloudDriveSync.swift` | `replica/Sources/BlinkClipCore/ICloudDriveSync.swift` |
| `replica/Sources/SnapclipCore/OriginalImagePreviewMetadata.swift` | `replica/Sources/BlinkClipCore/ImagePreviewMetadata.swift` |
| `replica/Sources/SnapclipCore/OriginalImagePreviewMetadataCodec.swift` | `replica/Sources/BlinkClipCore/ImagePreviewMetadataCodec.swift` |
| `replica/Sources/SnapclipCore/OriginalInitializedValue.swift` | `replica/Sources/BlinkClipCore/InitializedValue.swift` |
| `replica/Sources/SnapclipCore/OriginalItemPreviewView.swift` | `replica/Sources/BlinkClipCore/ItemPreviewView.swift` |
| `replica/Sources/SnapclipCore/OriginalItemTitleLabel.swift` | `replica/Sources/BlinkClipCore/ItemTitleLabel.swift` |
| `replica/Sources/SnapclipCore/KeyboardShortcut.swift` | `replica/Sources/BlinkClipCore/KeyboardShortcut.swift` |
| `replica/Sources/SnapclipCore/OriginalLayerBackedView.swift` | `replica/Sources/BlinkClipCore/LayerBackedView.swift` |
| `replica/Sources/SnapclipCore/OriginalLinkDisplay.swift` | `replica/Sources/BlinkClipCore/LinkDisplay.swift` |
| `replica/Sources/SnapclipCore/OriginalManagedItem.swift` | `replica/Sources/BlinkClipCore/ManagedItem.swift` |
| `replica/Sources/SnapclipCore/Models.swift` | `replica/Sources/BlinkClipCore/Models.swift` |
| `replica/Sources/SnapclipCore/OriginalNativeDragPasteboardWriter.swift` | `replica/Sources/BlinkClipCore/NativeDragPasteboardWriter.swift` |
| `replica/Sources/SnapclipCore/OCR.swift` | `replica/Sources/BlinkClipCore/OCR.swift` |
| `replica/Sources/SnapclipCore/OriginalObjCExceptionBridge.swift` | `replica/Sources/BlinkClipCore/ObjCExceptionBridge.swift` |
| `replica/Sources/SnapclipCore/OriginalOrderedSelection.swift` | `replica/Sources/BlinkClipCore/OrderedSelection.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteKeyTranslation.swift` | `replica/Sources/BlinkClipCore/PasteKeyTranslation.swift` |
| `replica/Sources/SnapclipCore/Pasteboard.swift` | `replica/Sources/BlinkClipCore/Pasteboard.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteboardCaptureState.swift` | `replica/Sources/BlinkClipCore/PasteboardCaptureState.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteboardClassification.swift` | `replica/Sources/BlinkClipCore/PasteboardClassification.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteboardDataCodec.swift` | `replica/Sources/BlinkClipCore/PasteboardDataCodec.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteboardImageEncoding.swift` | `replica/Sources/BlinkClipCore/PasteboardImageEncoding.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteboardImageRestore.swift` | `replica/Sources/BlinkClipCore/PasteboardImageRestore.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteboard.swift` | `replica/Sources/BlinkClipCore/PasteboardItem.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteboardPolicies.swift` | `replica/Sources/BlinkClipCore/PasteboardPolicies.swift` |
| `replica/Sources/SnapclipCore/OriginalPasteboardRestore.swift` | `replica/Sources/BlinkClipCore/PasteboardRestore.swift` |
| `replica/Sources/SnapclipCore/PermissionPromptPolicy.swift` | `replica/Sources/BlinkClipCore/PermissionPromptPolicy.swift` |
| `replica/Sources/SnapclipCore/PermissionStatusSnapshot.swift` | `replica/Sources/BlinkClipCore/PermissionStatusSnapshot.swift` |
| `replica/Sources/SnapclipCore/OriginalPinboardAttributes.swift` | `replica/Sources/BlinkClipCore/PinboardAttributes.swift` |
| `replica/Sources/SnapclipCore/OriginalPinboardColor.swift` | `replica/Sources/BlinkClipCore/PinboardColor.swift` |
| `replica/Sources/SnapclipCore/OriginalPinboardTitle.swift` | `replica/Sources/BlinkClipCore/PinboardTitle.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewAttributedText.swift` | `replica/Sources/BlinkClipCore/PreviewAttributedText.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewFooter.swift` | `replica/Sources/BlinkClipCore/PreviewFooter.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewPopover.swift` | `replica/Sources/BlinkClipCore/PreviewPopover.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewSharing.swift` | `replica/Sources/BlinkClipCore/PreviewSharing.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewTextColors.swift` | `replica/Sources/BlinkClipCore/PreviewTextColors.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewTextTraits.swift` | `replica/Sources/BlinkClipCore/PreviewTextTraits.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewTitleLabel.swift` | `replica/Sources/BlinkClipCore/PreviewTitleLabel.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewWindowTransition.swift` | `replica/Sources/BlinkClipCore/PreviewWindowTransition.swift` |
| `replica/Sources/SnapclipCore/OriginalPreviewWindows.swift` | `replica/Sources/BlinkClipCore/PreviewWindows.swift` |
| `replica/Sources/SnapclipCore/OriginalResourceBundle.swift` | `replica/Sources/BlinkClipCore/ResourceBundle.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchAppearance.swift` | `replica/Sources/BlinkClipCore/SearchAppearance.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchCommands.swift` | `replica/Sources/BlinkClipCore/SearchCommands.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchDateEncoding.swift` | `replica/Sources/BlinkClipCore/SearchDateEncoding.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchDateRanges.swift` | `replica/Sources/BlinkClipCore/SearchDateRanges.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchEditing.swift` | `replica/Sources/BlinkClipCore/SearchEditing.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchField.swift` | `replica/Sources/BlinkClipCore/SearchField.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchFieldAnimation.swift` | `replica/Sources/BlinkClipCore/SearchFieldAnimation.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchFilterView.swift` | `replica/Sources/BlinkClipCore/SearchFilterView.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchHistory.swift` | `replica/Sources/BlinkClipCore/SearchHistory.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchIndexingState.swift` | `replica/Sources/BlinkClipCore/SearchIndexingState.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchInputContext.swift` | `replica/Sources/BlinkClipCore/SearchInputContext.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchInputHistory.swift` | `replica/Sources/BlinkClipCore/SearchInputHistory.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchInputView.swift` | `replica/Sources/BlinkClipCore/SearchInputView.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchMenu.swift` | `replica/Sources/BlinkClipCore/SearchMenu.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchQuery.swift` | `replica/Sources/BlinkClipCore/SearchQuery.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchQueryNormalization.swift` | `replica/Sources/BlinkClipCore/SearchQueryNormalization.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchSuggestionAnchor.swift` | `replica/Sources/BlinkClipCore/SearchSuggestionAnchor.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchSuggestions.swift` | `replica/Sources/BlinkClipCore/SearchSuggestions.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchTextScroller.swift` | `replica/Sources/BlinkClipCore/SearchTextScroller.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchTextTokens.swift` | `replica/Sources/BlinkClipCore/SearchTextTokens.swift` |
| `replica/Sources/SnapclipCore/OriginalSearchTextView.swift` | `replica/Sources/BlinkClipCore/SearchTextView.swift` |
| `replica/Sources/SnapclipCore/OriginalSelectionAppearance.swift` | `replica/Sources/BlinkClipCore/SelectionAppearance.swift` |
| `replica/Sources/SnapclipCore/OriginalSettingsIllustrations.swift` | `replica/Sources/BlinkClipCore/SettingsIllustrations.swift` |
| `replica/Sources/SnapclipCore/OriginalSharedDependencyCache.swift` | `replica/Sources/BlinkClipCore/SharedDependencyCache.swift` |
| `replica/Sources/SnapclipCore/OriginalShortcutCoding.swift` | `replica/Sources/BlinkClipCore/ShortcutCoding.swift` |
| `replica/Sources/SnapclipCore/OriginalShortcutControls.swift` | `replica/Sources/BlinkClipCore/ShortcutControls.swift` |
| `replica/Sources/SnapclipCore/OriginalShortcutFunctions.swift` | `replica/Sources/BlinkClipCore/ShortcutFunctions.swift` |
| `replica/Sources/SnapclipCore/OriginalShortcutMessages.swift` | `replica/Sources/BlinkClipCore/ShortcutMessages.swift` |
| `replica/Sources/SnapclipCore/OriginalShortcutRecorder.swift` | `replica/Sources/BlinkClipCore/ShortcutRecorder.swift` |
| `replica/Sources/SnapclipCore/OriginalShortcutRecorderView.swift` | `replica/Sources/BlinkClipCore/ShortcutRecorderView.swift` |
| `replica/Sources/SnapclipCore/OriginalShortcutValidation.swift` | `replica/Sources/BlinkClipCore/ShortcutValidation.swift` |
| `replica/Sources/SnapclipCore/OriginalSoundEffects.swift` | `replica/Sources/BlinkClipCore/SoundEffects.swift` |
| `replica/Sources/SnapclipCore/OriginalSourceApplication.swift` | `replica/Sources/BlinkClipCore/SourceApplication.swift` |
| `replica/Sources/SnapclipCore/OriginalSourceApplicationColors.swift` | `replica/Sources/BlinkClipCore/SourceApplicationColors.swift` |
| `replica/Sources/SnapclipCore/OriginalSourceApplicationImageColor.swift` | `replica/Sources/BlinkClipCore/SourceApplicationImageColor.swift` |
| `replica/Sources/SnapclipCore/OriginalStackTableController.swift` | `replica/Sources/BlinkClipCore/StackTableController.swift` |
| `replica/Sources/SnapclipCore/OriginalTextPreviewMetadata.swift` | `replica/Sources/BlinkClipCore/TextPreviewMetadata.swift` |
| `replica/Sources/SnapclipCore/OriginalTextPreviewModel.swift` | `replica/Sources/BlinkClipCore/TextPreviewModel.swift` |
| `replica/Sources/SnapclipCore/OriginalTextPreviewSubmission.swift` | `replica/Sources/BlinkClipCore/TextPreviewSubmission.swift` |
| `replica/Sources/SnapclipCore/OriginalToolbarButton.swift` | `replica/Sources/BlinkClipCore/ToolbarButton.swift` |
| `replica/Sources/SnapclipCore/OriginalViewAnimation.swift` | `replica/Sources/BlinkClipCore/ViewAnimation.swift` |
| `replica/Sources/SnapclipCore/OriginalWritingTools.swift` | `replica/Sources/BlinkClipCore/WritingTools.swift` |
| `replica/Sources/SnapclipHelper/HelperMain.swift` | `replica/Sources/BlinkClipHelper/HelperMain.swift` |
| `replica/Sources/SnapclipMCP/PastoMCP.swift` | `replica/Sources/BlinkClipMCP/BlinkClipMCP.swift` |
| `replica/Sources/SnapclipObjC/SnapclipKeyTranslation.m` | `replica/Sources/BlinkClipObjC/BlinkClipKeyTranslation.m` |
| `replica/Sources/SnapclipObjC/PRCloudKitEntitlements.m` | `replica/Sources/BlinkClipObjC/PRCloudKitEntitlements.m` |
| `replica/Sources/SnapclipObjC/PRGlassBackgroundWindow.m` | `replica/Sources/BlinkClipObjC/PRGlassBackgroundWindow.m` |
| `replica/Sources/SnapclipObjC/PRObjCExceptionCatcher.m` | `replica/Sources/BlinkClipObjC/PRObjCExceptionCatcher.m` |
| `replica/Sources/SnapclipObjC/PRPanelGlassBackground.m` | `replica/Sources/BlinkClipObjC/PRPanelGlassBackground.m` |
| `replica/Sources/SnapclipObjC/include/SnapclipKeyTranslation.h` | `replica/Sources/BlinkClipObjC/include/BlinkClipKeyTranslation.h` |
| `replica/Sources/SnapclipObjC/include/PRCloudKitEntitlements.h` | `replica/Sources/BlinkClipObjC/include/PRCloudKitEntitlements.h` |
| `replica/Sources/SnapclipObjC/include/PRGlassBackgroundWindow.h` | `replica/Sources/BlinkClipObjC/include/PRGlassBackgroundWindow.h` |
| `replica/Sources/SnapclipObjC/include/PRObjCExceptionCatcher.h` | `replica/Sources/BlinkClipObjC/include/PRObjCExceptionCatcher.h` |
| `replica/Sources/SnapclipObjC/include/PRPanelGlassBackground.h` | `replica/Sources/BlinkClipObjC/include/PRPanelGlassBackground.h` |
| `replica/Sources/SnapclipObjC/include/module.modulemap` | `replica/Sources/BlinkClipObjC/include/module.modulemap` |
| `replica/Tests/SnapclipCoreTests/ClipboardStoreTests.swift` | `replica/Tests/BlinkClipCoreTests/ClipboardStoreTests.swift` |
| `replica/Tests/SnapclipCoreTests/ValidationMain.swift` | `replica/Tests/BlinkClipCoreTests/ValidationMain.swift` |
| `replica/Tests/Native/SnapclipLegacyMigrationHarness.swift` | `replica/Tests/Native/BlinkClipLegacyMigrationHarness.swift` |
| `replica/Tests/Native/SnapclipOwnedResourcesHarness.swift` | `replica/Tests/Native/BlinkClipOwnedResourcesHarness.swift` |
| `replica/Tests/Native/OriginalCloudKitSyncHarness.swift` | `replica/Tests/Native/CloudKitSyncHarness.swift` |
| `replica/scripts/test-snapclip-legacy-migration.sh` | `replica/scripts/test-blinkclip-legacy-migration.sh` |
| `replica/scripts/test-snapclip-owned-resources.sh` | `replica/scripts/test-blinkclip-owned-resources.sh` |

## 3. Module / entity / identifier renames (bulk)

| Old | New | Notes |
|---|---|---|
| `Swift module `Pasto` (Package.swift target)` | ``BlinkClipApp`` | app target, `path: "Sources/BlinkClip"` |
| ``PastoItemEntity`, `PastoListEntity`, … (Core Data classes)` | ``BlinkClipItemEntity`, …` | class names, `@objc(...)` names and `NSStringFromClass` uses |
| ``PastoSourceVersion` (Info.plist key)` | ``BlinkClipSourceVersion`` |  |
| ``PastoCloudKitContainerIdentifier`` | ``BlinkClipCloudKitContainerIdentifier`` |  |
| ``PASTO_UPDATE_PRIVATE_KEY`` | ``BLINKCLIP_UPDATE_PRIVATE_KEY`` | release.yml, docs/APP_UPDATES.md |
| ``PASTO_*` env vars` | ``BLINKCLIP_*`` | scripts, CI |
| ``pasto-mcp` alias / product` | ``blinkclip-mcp`` | Package.swift product, build scripts |
| ``com.wiheads.paste.item-id` (pasteboard type)` | ``com.chrisli.blinkclip.item-id`` |  |
| ``com.wiheads.paste.logger`` | ``com.chrisli.blinkclip.logger`` |  |
| ``com.wiheads.paste.paste-stack-frame`` | ``com.chrisli.blinkclip.paste-stack-frame`` |  |
| ``com.wiheads.paste` / `com.wiheads.paste-direct` / `-setapp`` | ``com.chrisli.blinkclip` / `-direct` / `-setapp`` |  |
| ``iCloud.com.wiheads.paste`` | ``iCloud.com.example.other`` | placeholder; no iCloud container is used |
| ``com.pastereplica.*` internal keys` | ``com.chrisli.blinkclip.*`` |  |
| ``"paste-replica-panel"` window identifier` | ``"blinkclip-panel"`` |  |
| ``pasto.*` localization keys` | ``blinkclip.*`` | both `.strings` copies + Swift call sites |
| ``pasto-history` URL scheme` | ``blinkclip-history`` |  |
| ``pasto.icloud-drive.` / `pasto.cloudkit.` UserDefaults prefixes` | ``blinkclip.…`` |  |
| ``Original*` filenames (141 files)` | `descriptive names (`Original` prefix stripped)` | `OriginalPasteboard.swift` → `PasteboardItem.swift` (collision with `Pasteboard.swift`) |
| ``Original*` class/type names` | ``BlinkClip`-neutral descriptive names` | generic `Original(?=[A-Z])` → `` replace |

## 3b. capcap → blinkclip 技术标识改名（2026-11-14）

盘点后剩下的 `capcap` 技术标识：纯内部标识（无持久化语义）统一改为 `blinkclip.*`；需要跨版本传递的那一个（剪贴板类型）保留一个版本周期的双读双写。许可证文件名与 `Vendor/capcap/` 目录名按 MIT 归属要求原样保留，不在本表内。

| Old | New | Notes |
|---|---|---|
| ``capcap.*` NSColor.Name（9 个语义色名）` | ``blinkclip.*`` | `Vendor/capcap/UI/AdaptiveChrome.swift`；纯进程内色名，无持久化语义 |
| ``capcap.*` DispatchQueue / 定时器标签（7 个）` | ``blinkclip.*`` | 队列标签只用于调试器与 `os_signpost`，不入档 |
| ``capcap.*` Notification.Name（12 个）` | ``blinkclip.*`` | 全部走 `NotificationCenter.default`，同进程同版本，没有跨进程/跨版本通信依赖 |
| ``capcap.toolbar.*` accessibilityIdentifier` | ``blinkclip.toolbar.*`` | 仅测试与辅助功能读取，未写入任何持久化格式 |
| ``capcap-edit` / `capcap-pin-drag` / `capcap-pin-<uuid>.png` 临时路径前缀` | ``blinkclip-…`` | 临时目录每次启动自建，旧目录残留由系统清理 |
| ``----capcap-<uuid>` multipart 边界` | ``----blinkclip-<uuid>`` | 只在单个上传请求内可见 |
| ``cn.skyrin.capcap.skip-clipboard-text-history`（剪贴板类型）` | ``com.chrisli.blinkclip.skip-clipboard-text-history`` | 双读双写一个版本周期：先读新名、回退旧名，写入同时写旧名别名（`ClipboardHistorySkipMarker`） |
| ``capcap.harness.*` 测试 UserDefaults suite` | ``blinkclip.harness.*`` | 测试专用隔离 suite，不承载用户数据 |

## 4. Comment-only `f_100xxx` references (no definition existed; rewritten as plain descriptions)

| Old reference | Rewritten to | File |
|---|---|---|
| `f_10007acd8` | Decorates the actual content; text keeps the zero border. | `BlinkClip/UI/ReplicaPreviewAdapter.swift` |
| `f_10007c994` | Without a PreferredSize provider, a quarter screen or zero is used. | `BlinkClip/UI/ReplicaColorPreviewContent.swift` |
| `f_1000ce644`/`f_1000ce5bc` | Uses the AppKit image initializer and body symbol style. | `BlinkClip/AppIntents/BlinkClipPinboardAppIntents.swift` |
| `f_1000cef84` | Projects only the decoded pinboard attributes into the … | `BlinkClip/AppIntents/BlinkClipPinboardAppIntents.swift` |
| `f_10022df78` | Normal, command-toggle, and anchored range selection. | `BlinkClipCore/OrderedSelection.swift` |
| `f_1002dcf24` | This is the generic dropLast operation. | `BlinkClipCore/SearchSuggestions.swift` |
| `f_1003189b0` | The local URL label value. | `BlinkClipCore/LinkDisplay.swift` |
| `f_100319778` | The local initial value, before its optional asynchronous provider branch. | `BlinkClipCore/LinkPreviewMetadata.swift` |
| `f_1003bf65c` | Traps when canonical metadata is absent or is not a link. | `BlinkClip/UI/ReplicaLinkPreviewContent.swift` |
| `f_1003c05d4` | Reads only the first representation. | `BlinkClip/UI/ReplicaPreviewAdapter.swift` |
| `f_1003d8588` | The three independent constraint values. | `BlinkClipCore/CardPresentation.swift` |
| `f_1003e1fec` | Compares the panel's value after updating the displayed content. | `BlinkClip/UI/ReplicaColorPreviewContent.swift` |
| `f_1003e2eac` | Closes the preview independently of the model action. | `BlinkClip/UI/ReplicaFilePreviewContent.swift` |
| `f_1003e3eec` | Both PreferredSizeProviding witnesses use half screen or zero. | `BlinkClip/UI/ReplicaFilePreviewContent.swift, ReplicaLinkPreviewContent.swift` |
| `f_1003ec168` | Measures the stored value, not the editing text. | `BlinkClip/UI/ReplicaPreviewAdapter.swift` |

## 5. Placeholders

None. No `blinkclipFunction<address>` placeholder names remain; every renamed
function has a descriptive name. Two same-name groups are intentional overloads
(different signatures): `ObjCExceptionBridge.withResult` (Void vs Data) and
`LayerBackedView.updateLayerColors` (static vs instance).
