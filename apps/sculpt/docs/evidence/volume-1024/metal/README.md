# Actual Metal measurements

Optimized Swift release tests at source `619a0efc2fd41b51e02daacbce4e7404546fd8d9` ran both worlds on Apple M1 Ultra, macOS 26.5.2 build 25F84, with 64 GiB system memory. The actual SceneKit renderer reported Metal and the Apple M1 Ultra device. Each case has 120 CPU camera submissions and 12 synchronized offscreen frames at 800 by 600 pixels. The test passed in 23.189 seconds. Raw samples, scene counters, mesh bytes, preparation timings and image coverage are retained in [receipt.json](receipt.json); the command log is [metal-tests.log](../verification/metal-tests.log).

| World | Case | Detailed | Proxy | Omitted | Distance culled | CPU camera median ms | Offscreen frame median ms | Offscreen frame maximum ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dense-equivalent | center-narrow | 20 | 188 | 0 | 3888 | 0.004833 | 3.057 | 7.916 |
| dense-equivalent | center-wide | 20 | 492 | 3584 | 0 | 0.005083 | 3.153 | 5.550 |
| dense-equivalent | shifted-narrow | 20 | 124 | 0 | 3952 | 0.005083 | 2.641 | 7.510 |
| dense-equivalent | ground-narrow | 20 | 119 | 0 | 3957 | 0.005125 | 2.661 | 5.726 |
| dense-equivalent | wide-detail-budget | 20 | 492 | 3584 | 0 | 0.004666 | 3.092 | 3.994 |
| landscape | center-narrow | 1 | 1 | 0 | 278 | 0.005083 | 1.770 | 6.804 |
| landscape | center-wide | 4 | 276 | 0 | 0 | 0.004875 | 2.300 | 7.074 |
| landscape | shifted-narrow | 1 | 0 | 0 | 279 | 0.005083 | 1.626 | 5.232 |
| landscape | ground-narrow | 20 | 22 | 0 | 238 | 0.005041 | 2.187 | 5.699 |
| landscape | wide-detail-budget | 33 | 247 | 0 | 0 | 0.005042 | 2.546 | 6.263 |

All camera samples retained the installed model meshes: one solid mesh or eight landscape meshes. Visible instances never exceeded 512 and rendered exterior faces stayed below 500,000. The solid world prepared 24,576 faces once; the landscape prepared 146,918 faces across its eight leaves. Instances share those prepared geometries. Chunk boundary surfaces are not globally merged. The wide solid cases omit 3584 placements because of the instance budget; the wide landscape detail case substitutes 247 proxies because of the face budget.

PNG files are actual offscreen Metal snapshots at samples 0 and 3, two per case. Pixel coverage was compared against an independently captured empty Metal view, rather than accepting any colored background as content. Root visually inspected four representative images; the scoped agent review records inspection of the remaining images.

Snapshot timing includes SceneKit flush, GPU synchronization and readback. PNG encoding and pixel analysis are excluded. CPU submission time is measured separately and does not establish end-to-end frame latency. These measurements are not on-screen FPS, a billion individual GPU cubes, a whole-world surface renderer, or a prediction for other hardware. The clutter of wireframe proxies is visible in the wide snapshots and remains a useful follow-up design case.
