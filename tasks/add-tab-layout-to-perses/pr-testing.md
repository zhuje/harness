```
# From dashboards shared package, install the spec locally
cd <path-to-shared>/dashboards && npm install ../../spec/ts
# Build the shared packages 
cd ../ && npm run build

# link perses from shared packages
./scripts/link-with-perses/link-with-perses.sh --perses ../perses

# install perses go spec from the branch
cd <path-to-perses> && go get github.com/perses/spec@520845b679baf56fc8fee810b86def06490d07fa
# start perses backend and frontend
./scripts/api_backend_dev.sh --e2e
cd ui/app && npm start:shared
```
