/// Moved to `package:leonard_contract` (lenny-9kni Stage 1). Re-exported
/// here so existing `package:leonard_flutter/...` imports and the public
/// `contract.dart` barrel keep resolving unchanged.
library;

export 'package:leonard_contract/leonard_contract.dart'
    show JsonSchema, ToolResult, BusyState, ExecutedAction;
