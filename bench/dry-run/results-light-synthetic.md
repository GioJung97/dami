# Phase 0 benchmark results

| config | EN WER | KO CER | MIXED CER | EN kept | latency (median) | latency (max) | RAM added (peak) | min free |
|---|---|---|---|---|---|---|---|---|
| wk-turbo-632mb-prompt | 4.6% | 0.5% | 25.4% | 57.1% | 0.74s | 0.80s | 627 MB | 43% |
| wk-turbo-632mb | 3.9% | 0.5% | 41.9% | 32.1% | 0.56s | 1.26s | 704 MB | 42% |

## Clips with errors

| config | id | reference | transcript | err |
|---|---|---|---|---|
| wk-turbo-632mb-prompt | en03 | Let's meet at 3, no, actually 4 p.m. at the coffee shop near the office. | Let's meet at 3, no, actually 4pm at the coffee shop near the office. | 12% |
| wk-turbo-632mb-prompt | en04 | The API returns a 404 when the user ID is missing from the request header. | The API returns a 400 for when the user ID is missing from the request header. | 13% |
| wk-turbo-632mb-prompt | en07 | I deployed the Supabase migration and updated the environment variables in Vercel. | I deployed the Supabase migration and updated the environment variables in Versil. | 8% |
| wk-turbo-632mb-prompt | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you, like, check whether the clog code hooks are running before each commit? | 7% |
| wk-turbo-632mb-prompt | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 솔직히, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| wk-turbo-632mb-prompt | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭐 먹을지 아직 못 청했어? | 7% |
| wk-turbo-632mb-prompt | mx02 | 이거 pull request 올렸으니까 review 좀 부탁해. | 이거 어플 리퀘스트 올렸으니까 리뷰 좀 부탁해. | 61% |
| wk-turbo-632mb-prompt | mx03 | 음, Supabase migration은 다음 주에 하는 걸로 하자. | 음, superbase migration은 다음 주에 하는 걸로 하자. | 7% |
| wk-turbo-632mb-prompt | mx04 | API key를 environment variable로 옮겨야 할 것 같아요. | API 키를 environment variable로 옮겨야 할 것 같아요. | 9% |
| wk-turbo-632mb-prompt | mx05 | 내일 deadline이라서 오늘 밤에 deploy 해야 돼. | 내일 데드라인이라서 오늘 밤에 데플로이 해야 돼. | 54% |
| wk-turbo-632mb-prompt | mx07 | Claude Code로 refactoring 했더니 훨씬 깔끔해졌어. | 클로드 코드로 리팩터링 했더니 훨씬 깔끔해졌어. | 66% |
| wk-turbo-632mb-prompt | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | 어, 그 bug는 production에서만 재현이 돼서 디버깅이 어려워. | 25% |
| wk-turbo-632mb-prompt | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning day 티켓 우선순위 다시 정하자. | 24% |
| wk-turbo-632mb | en03 | Let's meet at 3, no, actually 4 p.m. at the coffee shop near the office. | Let's meet at 3, no, actually 4pm at the coffee shop near the office. | 12% |
| wk-turbo-632mb | en04 | The API returns a 404 when the user ID is missing from the request header. | The API returns a 400 for when the user ID is missing from the request header. | 13% |
| wk-turbo-632mb | en07 | I deployed the Supabase migration and updated the environment variables in Vercel. | I deployed the Supabase migration and updated the environment variables in Versil. | 8% |
| wk-turbo-632mb | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you, like, check whether the clog code hooks are running before each commit? | 7% |
| wk-turbo-632mb | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭐 먹을지 아직 못 청했어? | 7% |
| wk-turbo-632mb | mx01 | 오늘 meeting에서 project timeline 얘기했어. | 오늘 미팅에서 프로젝트 타임라인 얘기했어. | 73% |
| wk-turbo-632mb | mx02 | 이거 pull request 올렸으니까 review 좀 부탁해. | 이거 어플 리퀘스트 올렸으니까 리뷰 좀 부탁해. | 61% |
| wk-turbo-632mb | mx03 | 음, Supabase migration은 다음 주에 하는 걸로 하자. | 음, Superbase Migration은 다음 주에 하는 걸로 하자. | 7% |
| wk-turbo-632mb | mx04 | API key를 environment variable로 옮겨야 할 것 같아요. | API 키를 environment variable로 옮겨야 할 것 같아요. | 9% |
| wk-turbo-632mb | mx05 | 내일 deadline이라서 오늘 밤에 deploy 해야 돼. | 내일 데드라인이라서 오늘 밤에 데플로이 해야 돼. | 54% |
| wk-turbo-632mb | mx07 | Claude Code로 refactoring 했더니 훨씬 깔끔해졌어. | 클로드 코드로 리팩터링 했더니 훨씬 깔끔해졌어. | 66% |
| wk-turbo-632mb | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | 어, 그 버그는 프로덕션에서만 재현이 돼서 디버깅이 어려워. | 61% |
| wk-turbo-632mb | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 스프린트 플래닝 데이 티켓 우선순위 다시 정하자. | 64% |
