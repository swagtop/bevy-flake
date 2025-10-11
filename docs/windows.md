# Cross-compiling for Windows

As of `2025-06-02`, these are the Windows SDK and CRT versions that have been
tested, and confirmed to succesfully be fetched, and used for compiling the
`*-pc-windows-msvc` targets.

Only the compilation process is confirmed to be successful. You should check for
yourself if any issues show up at runtime.

Find more information about the versions of the SDK and CRT's here:
[Visual Studio Build Tools component directory][sdk_microsoft].

[sdk_microsoft]: https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools

If you get any version not listed here, please feel free to open an issue or
pull request where its added to the list. Likewise, please report if you find
any version no longer working.

## Supported Windows SDK versions

You cannot specify the build version with `xwin`, so the dates corresponding to
the version will be that of the latest build of the latest patch for the SDK.

More information on Windows SDK versions here: [Wikipedia][sdk_wiki].

[sdk_wiki]: https://en.wikipedia.org/wiki/Microsoft_Windows_SDK

The table is sorted from newest to oldest.

| Manifests  | SDK Version  | Release      |
|------------|--------------|--------------|
| `16`, `17` | `10.0.22621` | `2023-05-24` |
| `16`, `17` | `10.0.22000` | `2021-10-04` |
| `16`, `17` | `10.0.20348` | `2021-05-25` |
| `16`, `17` | `10.0.19041` | `2020-12-16` |
| `16`, `17` | `10.0.18362` | `2019-05-21` |
| `16`       | `10.0.17763` | `2018-10-02` |
| `16`       | `10.0.17134` | `2018-05-08` |

## Supported Windows CRT versions

The table is sorted from newest to oldest.

| Manifests  | CRT Version   |
|------------|---------------|
| `17`       | `14.44.17.14` |
| `17`       | `14.43.17.13` |
| `17`       | `14.42.17.12` |
| `17`       | `14.41.17.11` |
| `17`       | `14.40.17.10` |
| `17`       | `14.39.17.9`  |
| `17`       | `14.38.17.8`  |
| `17`       | `14.37.17.7`  |
| `17`       | `14.36.17.6`  |
| `17`       | `14.35.17.5`  |
| `17`       | `14.34.17.4`  |
| `17`       | `14.33.17.3`  |
| `17`       | `14.32.17.2`  |
| `17`       | `14.31.17.1`  |
| `17`       | `14.30.17.0`  |
| `17`       | `14.29.16.11` |
| `16`       | `14.29.16.10` |
