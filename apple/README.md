# ProLine CRM — Native Apple App

This is the shared SwiftUI implementation for iPhone, iPad and Mac, plus the WidgetKit Today widget.

```bash
cd apple
xcodegen generate
open ProLineCRM.xcodeproj
```

Select an Apple Development team for each target before running on a device. The App Group capability must use `group.com.prolineroofingandsolar.crm` for both apps and both widgets.

The first native milestone includes the existing CRM login, live Supabase REST data, an adaptive pipeline, job list, lead details, native stage updates, Notification Centre permission, Keychain session storage and shared iPhone/Mac widgets.
