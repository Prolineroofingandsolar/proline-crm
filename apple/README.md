# ProLine CRM — Native Apple App

This is the shared SwiftUI implementation for iPhone, iPad and Mac, plus the WidgetKit Today widget.

```bash
cd apple
xcodegen generate
open ProLineCRM.xcodeproj
```

`project.yml` is the source of truth for the Xcode project (entitlements, push environments and targets included); regenerate with `xcodegen generate` after adding files. Format Swift with `xcrun swift-format format --in-place --recursive --configuration Shared/.swift-format Shared App Widgets Tests`.

Select an Apple Development team for each target before running on a device. The App Group capability must use `group.com.prolineroofingandsolar.crm` for both apps and both widgets.

Debug builds accept `--worker-preview` or `--admin-preview` as launch arguments to run with sample data and no sign-in (Edit Scheme → Arguments).

Sign-in is Supabase Auth only; the old username/password-hash login has been removed from the native apps.

The first native milestone includes the existing CRM login, live Supabase REST data, an adaptive pipeline, job list, lead details, native stage updates, Notification Centre permission, Keychain session storage and shared iPhone/Mac widgets.
