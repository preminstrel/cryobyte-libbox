# Libbox for CryoByte

`Libbox.xcframework`, the Apple library of [sing-box](https://github.com/SagerNet/sing-box), as the CryoByte app's tunnel extensions link it. This repository only hosts the build and the script that makes it.

| | |
|---|---|
| sing-box | v1.14.4 (`c005f35300ce76427dc285481ec5695f5b179cd2`), unmodified |
| Go | 1.26.10 with sing-box's `go_ios_cpu_features.patch` |
| gomobile | `github.com/sagernet/gomobile` v0.1.13 |
| Slices | iOS arm64, iOS Simulator arm64 + x86_64, macOS arm64 + x86_64 (static) |
| Download | [Release v1.14.4](../../releases/tag/v1.14.4) → `Libbox.xcframework.zip` |
| sha256 | `02e62904d30bfb536fb6e5bf060d9c0928122bd7d5daad50d764d5ab23d09be8` |

`build-libbox.sh` builds it from sing-box's source; the build tags it uses are listed there. A rebuild gives the same library but a different zip hash.

The frameworks are static: link them, don't embed them. A target that links one also needs `-lresolv` and `Network.framework`, and on iOS `UIKit.framework`.

## License

sing-box is licensed under the GNU General Public License v3.0 or later, and so is this build: see `LICENSE` and sing-box's notice in `NOTICE`. Its source is at https://github.com/SagerNet/sing-box/tree/v1.14.4. This repository is not affiliated with sing-box or SagerNet.
