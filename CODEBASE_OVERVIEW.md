# Movie-Application — Codebase Overview

A full-stack **movie catalog app** built on the classic MySQL **Sakila** sample
database, designed primarily as a DevOps/deployment learning project
(Docker → Kubernetes → AWS EKS).

## Architecture

```
┌─────────────┐      REST/JSON      ┌──────────────┐      JPA/JDBC      ┌─────────────┐
│  Angular 11 │ ──────────────────► │ Spring Boot  │ ─────────────────► │ MySQL       │
│  (frontend) │   :8080/api/film    │   2.4.5      │                    │ (Sakila DB) │
│   :4200     │                     │  (backend)   │                    │  :3306      │
└─────────────┘                     └──────────────┘                    └─────────────┘
```

It is a Maven **multi-module** project (`pom.xml` → `movie-backend`, `movie-frontend`).

## Backend — `movie-backend/` (Java 8, Spring Boot 2.4.5)

Standard layered architecture under `com.spring.boot.movie.app`:

- **`model/`** — JPA entities mapping the Sakila schema: `Film`, `Actor`,
  `Category`, `Language`, `Customer`, `Address`, `City`, `Country`, `Staff`,
  `Store` + enums (`Rating`, `SpecialFeatures`).
- **`repositories/`** — Spring Data JPA repositories.
- **`services/`** + **`services/implementaions/`** — interface + impl pattern for
  each entity.
- **`controller/`** — REST controllers. The main one is `FilmController`
  (`/api/film`) with endpoints: `getAllFilm`, `save`, `search/{title}`,
  `category/{value}`, `movieDetails/{id}`, `getAllFilmByActor/{id}`.
- **`configurations/`** — `MovieDSConfig`, `RestDataConfig`.
- Only one test: `FilmServiceImplTest`.
- Spring Boot Actuator exposes `/actuator/health` for k8s probes.

## Frontend — `movie-frontend/` (Angular 11)

- **Components**: `movie-list`, `movie-details`, `add-film`, `actor-list`,
  `search`, `movie-category-menu`, `login`.
- **Services**: `movie.service.ts`, `actor.service.ts`, `category.service.ts`,
  `movie-form.service.ts`.
- **Models**: `movie`, `actor`, `category`, `language`.
- Uses `@ng-bootstrap`, Bootstrap 4, FontAwesome.
- Routing redirects `/` → `/movies`.

## Running Locally (verified baseline)

The app runs end-to-end on its **original, compatible runtimes** (modern Java 25 /
Node 24 are too new for Spring Boot 2.4.5 / Angular 11):

| Tier | Version | Endpoint |
|---|---|---|
| MySQL (Sakila) | 8.0 (Docker) | `localhost:3306` |
| Spring Boot backend | 2.4.5 on **JDK 8** | `localhost:8080` |
| Angular frontend | 11 on **Node 12.22** | `localhost:4200` |

Prerequisites: **JDK 8**, **Node 12** (e.g. via `nvm install 12`), and **Docker**.

```bash
# 1. Database (loads Sakila on first boot)
cd docker-test-db && docker compose up -d        # stop: docker compose down

# 2. Backend — from project root, datasource passed via env vars
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk1.8.0_231.jdk/Contents/Home
export SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/sakila?allowPublicKeyRetrieval=true&useSSL=false"
export SPRING_DATASOURCE_USERNAME=root SPRING_DATASOURCE_PASSWORD=root
mvn -pl movie-backend spring-boot:run

# 3. Frontend
cd movie-frontend && nvm use 12 && npm start
```

Then open <http://localhost:4200>. The datasource is supplied via environment
variables because the active block in `application.properties` is EKS-only
(see Observation #6); no source files need editing to run locally.

### Helper scripts (`scripts/`)

**Lifecycle (one command up/down):**

- **`scripts/start-local.sh`** — brings up the whole baseline: starts the MySQL
  container and waits for Sakila to load, launches the backend on JDK 8, then the
  Angular dev server on Node 12 (both backgrounded). Logs/PIDs go to
  `scripts/logs/` (git-ignored). Honors `JAVA_8_HOME` and `NODE_VERSION`.
- **`scripts/stop-local.sh`** — tears it all back down (frontend, backend, then
  the MySQL container). Pass `--keep-db` to leave MySQL running.

```bash
./scripts/start-local.sh    # DB + backend + frontend
./scripts/stop-local.sh     # stop everything (add --keep-db to keep MySQL)
```

**Baseline tests:**

- **`scripts/smoke-test.sh`** — end-to-end smoke test of the running stack:
  checks the MySQL container + Sakila seed data, the five `FilmController` REST
  endpoints, and that the Angular dev server serves the app shell. Prints a
  PASS/FAIL summary and exits non-zero on any failure. Honors `BACKEND_URL`,
  `FRONTEND_URL`, and `DB_CONTAINER` env overrides.
- **`scripts/backend-test.sh`** — runs the backend unit tests via Maven, pinning
  `JAVA_HOME` to a JDK 8 install (override with `JAVA_8_HOME`).

```bash
./scripts/smoke-test.sh     # verify the running baseline (9 checks)
./scripts/backend-test.sh   # run mvn unit tests on JDK 8
```

These give a quick regression check to confirm the app still behaves the same
before and after the planned version upgrade.

## Deployment / DevOps (the project's main focus)

### Two `docker-compose.yml` files (different workflows)

The project ships **two** compose files that are *not* meant to run together:

| | `docker-test-db/docker-compose.yml` | root `docker-compose.yml` |
|---|---|---|
| Services | MySQL only | MySQL + backend + frontend |
| MySQL image | `mysql:8.0` (pinned) | `sakila-docker-db` (built from `DockerFileMySQLDb`) |
| MySQL port | `3306` | `3305` |
| Backend/Frontend | run natively on host | run in containers |
| Use case | local dev (DB-only inner loop) | full containerized stack / demo |

- **`docker-test-db/docker-compose.yml`** — lightweight, **database only**. Spins
  up MySQL with the Sakila dump auto-loaded so you can run the backend/frontend
  natively on the host. This is the recommended local-dev path.
- **`docker-compose.yml`** (root) — the **whole app** (db + backend + frontend),
  built from `Dockerfile`, `Dockerfile-npm`, and `DockerFileMySQLDb`. One command
  (`docker-compose up -d --build`) brings up the full stack with no host
  JDK/Node needed.

> Both bind MySQL (3306 vs 3305) and share backend/frontend ports, so run only
> one at a time.

### Other deployment assets

- **`Dockerfile`** (backend jar), **`Dockerfile-npm`** (Angular),
  **`DockerFileMySQLDb`** (custom Sakila image).
- **`k8s-deployments/`** — individual manifests (namespace, db
  deployment/svc/pvc/configmap/secrets, spring-boot app, angular app).
- **`eks-deployment/`** — single consolidated AWS EKS manifest with `gp3`
  StorageClass (EBS CSI), MySQL deployment, backend ClusterIP, frontend
  **LoadBalancer**.
- **`Jenkinsfile`** — CI/CD pipeline: Git pull → `mvn clean install` →
  `kubectl apply` to a microk8s cluster via SSH.
- **`mysql-dump/`** & **`docker-test-db/`** — Sakila SQL seed scripts.

## Notable Observations

1. **Hardcoded API URL** — `movie.service.ts:15` hardcodes
   `http://localhost:8080/api/film` instead of using `environment.ts`. The EKS
   frontend passes a `BACKEND_API_URL` env var that the Angular code never reads,
   so the deployed frontend cannot reach the backend as-is.
2. **Plaintext DB credentials** (`root`/`root`) committed in `docker-compose.yml`,
   k8s secrets, and the EKS manifest.
3. **Duplicate routes** in `app.module.ts` (`category/:id` and `category`
   declared twice).
4. **No backend auth** — there is a `login` component on the frontend but no
   corresponding security on the API.
5. **Readme typo** — `mvn clan install` should be `mvn clean install`.
6. **Mixed-config `application.properties`** — only the EKS block is active;
   Docker/k8s blocks are commented out and rely on env-var substitution.
7. **`mysql:latest` crash-loop** — `DockerFileMySQLDb` (and originally
   `docker-test-db/docker-compose.yml`) used `mysql:latest`, which now resolves to
   MySQL 9.x and removes the `--default-authentication-plugin=mysql_native_password`
   option, causing the container to abort on startup. The test-db compose has been
   pinned to `mysql:8.0`; `DockerFileMySQLDb` still needs the same fix.
