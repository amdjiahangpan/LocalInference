# LocalInference

ROSCon 2026 workshop on local robot inference with an AMD Ryzen AI Max (Strix Halo) iGPU. The labs walk through four steps:

- serve language and vision models with Lemonade
- drive a simulated Franka Panda arm with them over ROS 2 (RAI)
- have a model write the robot's control code (CaP-X)
- read how a coding agent optimized that code (RHO)

Every model runs on the local machine.

This repository contains the course image and everything it ships: the Dockerfile, the build and run scripts, and the notebooks with their helper scripts and assets. It was extracted from [AMDResearch/aup-learning-cloud](https://github.com/AMDResearch/aup-learning-cloud) (`dockerfiles/Courses/LocalInference` and `projects/LocalInference`).

## Labs

Complete the notebooks in order:

| Notebook | Kernel | Content |
| --- | --- | --- |
| `0_overview.ipynb` | RAI (ROCm) | Course overview |
| `1_local_inference.ipynb` | RAI (ROCm) | Serve Gemma with Lemonade and call its OpenAI-compatible API with text, images and speech |
| `2_robot_agents.ipynb` | RAI (ROCm) | Command a simulated Franka Panda in O3DE through an RAI agent over ROS 2 |
| `3_code_as_policy.ipynb` | CaP-X (ROCm) | Have the model write a Python policy, then run and score it in Robosuite/MuJoCo |
| `4_robot_harness_optimization.ipynb` | CaP-X (ROCm) | Read a recorded RHO evolution run, then replay the seed and deployed policies live |

## Repository layout

| Path | Content |
| --- | --- |
| `Dockerfile` | The course image, built on `ghcr.io/amdresearch/auplc-base` (ROCm 7.13 + PyTorch) |
| `build.sh`, `run.sh` | Build the image; start it as a standalone JupyterLab |
| `*.ipynb` | The labs |
| `scripts/` | Helpers the notebooks import: Lemonade, the RAI demo, CaP-X and RHO |
| `tests/` | Environment checks, available in the image as `/ryzers/test_*.sh` |
| `images/` | Figures used by the notebooks |
| `recorded_results/`, `fixtures/` | The recorded RHO study and the seed policies used by notebook 4 |

The image copies everything except the repository tooling into `/ryzers/notebooks`, which is also its working directory.

## Requirements

- An AMD Ryzen AI Max (Strix Halo, `gfx1151`) host whose amdgpu driver supports ROCm 7.13. The default base image targets `gfx1151`, and the runtimes below were measured on that hardware.
- Docker with BuildKit, which has been the default since Docker 23. The Dockerfile uses heredocs, which need BuildKit.
- Network access during the build (Ubuntu and ROS apt repositories, GitHub, PyPI, Hugging Face, `ghcr.io`). At runtime, network access is only needed for optional model pulls.

## Build

```bash
bash build.sh
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `IMAGE` | `ghcr.io/amdresearch/auplc-localinference:latest` | Tag to build |
| `BASE_IMAGE` | `ghcr.io/amdresearch/auplc-base:latest` | ROCm base image; choose the one that matches your GPU target |
| `HOST_RENDER_GID` | `992` | Host `render` group id that `jovyan` joins. Set it when JupyterHub or Kubernetes runs the image on nodes where `/dev/kfd` is not world-accessible. `run.sh` adds the host groups at runtime instead. |

The notebooks and scripts are copied into the image at build time, so rebuild after changing them.

## Run

The image's default command starts `jupyterhub-singleuser` for AUP Learning Cloud, which only works when JupyterHub spawns the container. To run the image on its own:

```bash
bash run.sh
docker logs -f auplc-li     # wait for "Jupyter Server ... is running at"
```

Then open `http://localhost:8888/lab?token=auplc`, or `http://<host-ip>:8888/lab?token=auplc` from another machine. Set `IMAGE`, `NAME`, `PORT` or `TOKEN` to override the defaults. Re-running `run.sh` replaces the existing container.

## Test

Run the environment checks before the notebooks:

```bash
for t in ros o3de rai lemonade-sdk capx rho rho_multitask; do
  echo "=== $t ==="; docker exec auplc-li /ryzers/test_$t.sh || break
done
```

- `test_lemonade-sdk.sh` kills every `lemond` process when it exits, which is why these checks come before the notebooks.
- `test_capx.sh` checks that ROCm PyTorch sees the GPU and runs one oracle episode without an LLM. Its LLM stage only runs when Lemonade is already serving or `CAPX_LLM_SERVER_URL` is set.
- `test_rho.sh` runs static checks only. Set `RHO_RUN_LIVE=1` to add one real mutation.

Then run the notebooks in order in JupyterLab. Notebook 1 expects Lemonade to be running already, so start it from a JupyterLab terminal as the notebook describes:

```bash
HF_HOME="$LEMONADE_HF_HOME" lemond "$LEMONADE_CACHE" &
lemonade load Gemma-4-E2B-it-GGUF
```

Notebooks 2 to 4 start the services they need. Service logs are in the container's `/tmp`:

- `lemond.log`
- `demo_launch.log`
- `weston.log`
- `web_video_server.log`
- `capx-services.log`

## Notebook 4 — structure and time budget

Notebook 4 is built for a 15–20 minute guided session:

| Section | Content | Compute |
| --- | --- | --- |
| The experiment | Editable surface, `helix.toml`, evaluator boundary | pre-rendered |
| Running a full evolution | Printed commands to fetch the model and reproduce the study | printed, not run |
| Recorded run | Two-generation, two-task Qwen3-Coder evolution | pre-rendered |
| Start the robot services | OWLv2, SAM2, Contact-GraspNet, PyRoKi | live, ~10 s |
| Watch both policies run | Seed vs deployed, one trial per task | **live, ~55 s** |

The seed-vs-deployed replay is the only section that runs anything. It executes frozen Python against the robot services with no model in the control loop. The services cell therefore passes `model=None` and starts no model server. The recorded run supplies the rest of the notebook: the search-progress plot, the lineage and gate decisions, and the deployed diff split per file.

Both policies narrate themselves during the replay. `rho_demo` marks each line the sandbox prints, and `rho_report.rollout_narrator()` forwards it. The output arrives as the robot reaches each stage instead of appearing at the end. The seed stops mid-task where it raises; the deployed policy runs on through placement and release.

The 30B mutation model is **not** in the image. Notebook 4 never calls a language model, so caching 18 GB for one opt-in path is not worth it. The notebook prints the `lemonade pull` command that fetches and registers it, next to the study command it feeds.

Every score the notebook shows comes from the six validation trials the search optimized against. This keeps the session short, but those scores say nothing about generalization. The notebook states this limit where it reports the numbers. It also points at the deployed repository for anyone who wants to replay it on trials the search never saw.

### Reproducibility of a trial

`rho_demo.seed_scene()` reseeds the robosuite placement generator in place from the trial id before every reset, so one trial now means one scene. Without this fix, the same trial drew different object positions on every evaluation:

- Robosuite builds the placement generator when the environment is constructed, and CaP-X passes no seed.
- The gym wrapper's `reset(seed=...)` only touches the legacy global `np.random`, which the placement sampler never reads.

Grasp sampling still varies, because it runs in the perception service rather than the evaluation worker. Replayed five times on each of the six validation trials, the deployed policy solves 19 of 30 and the seed 0 of 30. The recorded study predates the seeding fix, so each of its per-trial scores is a single draw. `scripts/rho_replay_scan.py` reproduces the repeated measurement.

## Generating notebook 4's recorded assets

This repository already ships `recorded_results/`, so this is only needed to re-record the study. Run the commands inside the LocalInference image on a machine with the GPU. The mutation model is not baked into the image, so fetch it first:

```bash
lemonade pull user.Qwen3-Coder-30B-A3B-Instruct-Q4_K_M \
  --checkpoint main \
    unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf \
  --recipe llamacpp \
  --label coding

python /ryzers/notebooks/scripts/rho_multitask_study.py \
  --output-dir /ryzers/notebooks/recorded_results \
  --model user.Qwen3-Coder-30B-A3B-Instruct-Q4_K_M \
  --generations 2 \
  --proposals 4 \
  --minibatch-size 2 \
  --hidden-repeats 3
```

`--generations 2` is short on purpose. A six-generation version of this experiment was run first, and everything it achieved landed in generation 1. The extra generations rejected most of their proposals. The candidate they deployed differed from the generation-1 winner only by a `try/except` that re-raises.

Notebook 4 needs only two things out of that run:

- `rho_multitask_report.json` — schema `rho-multitask-helix-report/v2`
- `repos/seed/` and `repos/selected/` — the two policy repositories the live
  replay cell runs

The study also writes `videos/` and replays a set of trials the search never sampled, controlled by `--hidden-repeats`. The notebook renders neither, because it replays both policies live instead. `videos/` is the only large thing the study produces, and this repository has no Git LFS configuration. It is therefore ignored by both git and Docker. Without it the recorded tree is about 230 KB.

Copy the resulting tree back to `recorded_results/` in this repository so that `build.sh` bakes it into the image. Verify it from the notebook's preflight cell or directly:

```bash
python -c "import sys; sys.path.insert(0, 'scripts'); import rho_report; \
print(rho_report.format_preflight(rho_report.preflight('recorded_results')))"
```

Media paths are stored relative to the recorded root, so a study produced on one host replays correctly from `/ryzers/notebooks/recorded_results` in the image.

## Recorded study evidence

`recorded_results/` holds everything notebook 4 reads:

- `rho_multitask_report.json`: the recorded two-generation run. It carries the
  per-instance frontier, the selected candidate and its diff, the hidden-trial
  scores before and after evolution, and the study provenance.
- `repos/seed/` and `repos/selected/`: the seed repository and the deployed one,
  as plain Python the notebook diffs and executes.

Rebuild both with the commands under "Generating notebook 4's recorded assets".

## Measured workshop runtime

Measured on the workshop Strix Halo GPU:

- CaP-X: 4.5 seconds for model setup, 11.4 seconds for perception/control
  setup, 14.2 seconds for one LLM call, and 11.8 seconds for one rollout.
- RHO service startup: the `ensure_services` cell sits immediately above the
  live replay, so nothing loads OWLv2, SAM2, Contact-GraspNet or PyRoKi until
  the notebook needs them. Run it early if you would rather pay the cost before
  the session; it is idempotent and the later cell will reuse what is running.
- RHO seed-vs-deployed replay: four rollouts, two per task, 10 to 16 seconds
  each. This is the only live compute in the notebook. The seed crashes every
  time. Measured five times on each of the six validation trials, the deployed
  policy solved 19 of 30, so budget for the occasional miss rather than treating
  it as a failure. `scripts/rho_replay_scan.py` reproduces those pass rates, and
  `rho_report.validation_trial` uses them to pick the trial shown per task.
- RHO recorded run: reads `recorded_results/` and renders immediately.

## Baked models

The workshop's Gemma E2B and Gemma E4B GGUFs are baked under `/opt/lemonade-cache`, outside the JupyterHub home-volume mount.

The Qwen3-Coder mutation checkpoint is deliberately not baked in. Notebook 4 replays a recorded run and loads no language model, so reproducing the evolution means pulling the checkpoint first, as shown above.

SAM2.1 Large and OWLv2 Large are likewise baked under `/opt/capx-cache`. Neither runtime path needs a Hugging Face token or a first-run model download. Their checkpoints are staged through FP16 before an on-device FP32 conversion. This avoids a multi-minute ROCm transfer while keeping FP32 execution. Matching `*_fast.yaml` CaP-X configs keep SAM2.1 Small and OWLv2 Base for comparisons.

## License

MIT, see [LICENSE](LICENSE).
