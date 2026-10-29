# Phase 0 benchmark results

| config | EN WER | KO CER | MIXED CER | EN kept | latency (median) | latency (max) | RAM added (peak) | min free |
|---|---|---|---|---|---|---|---|---|
| adaptive-final | 1.3% | 5.1% | 11.7% | 82.1% | 0.74s | 0.83s | 524 MB | 41% |
| adaptive-vocab-ko | 1.3% | 5.1% | 14.1% | 92.9% | 0.90s | 1.10s | 576 MB | 42% |
| adaptive-vocab-v2 | 1.3% | 4.7% | 22.0% | 89.3% | 0.86s | 0.96s | 579 MB | 42% |
| adaptive-vocab | 1.3% | 5.1% | 14.1% | 92.9% | 0.91s | 1.03s | 524 MB | 42% |
| adaptive | 4.6% | 5.1% | 11.7% | 82.1% | 0.70s | 0.82s | 662 MB | 41% |
| wk-turbo-632mb-prompt | 5.9% | 5.1% | 11.7% | 82.1% | 0.73s | 0.82s | 481 MB | 41% |
| wk-turbo-632mb-vocab-en | 1.3% | 0.9% | 32.0% | 67.9% | 0.78s | 0.91s | 524 MB | 42% |
| wk-turbo-632mb-vocab-ko-sentence | 0.7% | 4.7% | 22.0% | 89.3% | 0.89s | 0.96s | 579 MB | 42% |
| wk-turbo-632mb-vocab-mixed-ko | 2.0% | 5.1% | 14.1% | 92.9% | 0.94s | 1.10s | 576 MB | 43% |
| wk-turbo-632mb-vocab-mixed | 2.0% | 5.1% | 14.1% | 92.9% | 0.95s | 1.03s | 519 MB | 42% |
| wk-turbo-632mb | 4.6% | 1.4% | 41.9% | 35.7% | 0.55s | 1.62s | 662 MB | 41% |

## Clips with errors

| config | id | reference | transcript | err |
|---|---|---|---|---|
| adaptive-final | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you like check whether the Claude Code hooks are running before each comment? | 7% |
| adaptive-final | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| adaptive-final | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| adaptive-final | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| adaptive-final | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 33% |
| adaptive-final | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| adaptive-final | mx03 | 음, Supabase migration은 다음 주에 하는 걸로 하자. | 음...superbase migration은 다음 주에 하는 걸로 하자. | 7% |
| adaptive-final | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, 이 부분을 조금 더 생각해봐야 할 것 같아. | 5% |
| adaptive-final | mx07 | Claude Code로 refactoring 했더니 훨씬 깔끔해졌어. | 클라우드 코드로 리팩터링 했더니 훨씬 깔끔해졌어. | 66% |
| adaptive-final | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | 그 bug는 production에서만 제안이 되어서 debugging이 어려워. | 11% |
| adaptive-final | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| adaptive-vocab-ko | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you like check whether the Claude Code hooks are running before each comment? | 7% |
| adaptive-vocab-ko | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| adaptive-vocab-ko | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| adaptive-vocab-ko | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| adaptive-vocab-ko | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 33% |
| adaptive-vocab-ko | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| adaptive-vocab-ko | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, I think this is a little more. | 105% |
| adaptive-vocab-ko | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | Bug는 production에서만 제안이 돼서 디버깅이 어려워. | 33% |
| adaptive-vocab-ko | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| adaptive-vocab-v2 | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you like check whether the Claude Code hooks are running before each comment? | 7% |
| adaptive-vocab-v2 | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| adaptive-vocab-v2 | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| adaptive-vocab-v2 | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| adaptive-vocab-v2 | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 그 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 29% |
| adaptive-vocab-v2 | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| adaptive-vocab-v2 | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, I think this is a little more about the part. | 159% |
| adaptive-vocab-v2 | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | 그 bug는 프로덕션에서만 제안이 되어서 디버깅이 어려워. | 64% |
| adaptive-vocab-v2 | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| adaptive-vocab | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you like check whether the Claude Code hooks are running before each comment? | 7% |
| adaptive-vocab | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| adaptive-vocab | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| adaptive-vocab | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| adaptive-vocab | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 33% |
| adaptive-vocab | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| adaptive-vocab | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, I think this is a little more. | 105% |
| adaptive-vocab | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | Bug는 production에서만 제안이 돼서 디버깅이 어려워. | 33% |
| adaptive-vocab | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| adaptive | en07 | I deployed the Supabase migration and updated the environment variables in Vercel. | I deployed the super-based migration and updated the environment variables in Versailles. | 25% |
| adaptive | en08 | Thanks for the quick reply. I'll review the pull request this afternoon and leave comments. | Thanks for the quick reply. I'll review the poll request this afternoon and leave comments. | 6% |
| adaptive | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you like check whether the Cloud Code hooks are running before each comment? | 14% |
| adaptive | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| adaptive | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| adaptive | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| adaptive | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 33% |
| adaptive | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| adaptive | mx03 | 음, Supabase migration은 다음 주에 하는 걸로 하자. | 음...superbase migration은 다음 주에 하는 걸로 하자. | 7% |
| adaptive | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, 이 부분을 조금 더 생각해봐야 할 것 같아. | 5% |
| adaptive | mx07 | Claude Code로 refactoring 했더니 훨씬 깔끔해졌어. | 클라우드 코드로 리팩터링 했더니 훨씬 깔끔해졌어. | 66% |
| adaptive | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | 그 bug는 production에서만 제안이 되어서 debugging이 어려워. | 11% |
| adaptive | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| wk-turbo-632mb-prompt | en04 | The API returns a 404 when the user ID is missing from the request header. | API returns a 404 when the user ID is missing from the request header. | 7% |
| wk-turbo-632mb-prompt | en05 | So basically what I'm trying to say is that the onboarding flow feels way too long. | 그래서, basically, what I'm trying to say is that the onboarding flow feels way too long. | 6% |
| wk-turbo-632mb-prompt | en07 | I deployed the Supabase migration and updated the environment variables in Vercel. | I deployed the superbase migration and updated the environment variables in Versil. | 17% |
| wk-turbo-632mb-prompt | en08 | Thanks for the quick reply. I'll review the pull request this afternoon and leave comments. | Thanks for the quick reply. I'll review the poll request this afternoon and leave comments. | 6% |
| wk-turbo-632mb-prompt | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you check whether the Cloud Code hooks are running before each comment? | 21% |
| wk-turbo-632mb-prompt | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 솔직히, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| wk-turbo-632mb-prompt | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| wk-turbo-632mb-prompt | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| wk-turbo-632mb-prompt | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 33% |
| wk-turbo-632mb-prompt | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| wk-turbo-632mb-prompt | mx03 | 음, Supabase migration은 다음 주에 하는 걸로 하자. | 음...superbase migration은 다음 주에 하는 걸로 하자. | 7% |
| wk-turbo-632mb-prompt | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, 이 부분을 조금 더 생각해봐야 할 것 같아. | 5% |
| wk-turbo-632mb-prompt | mx07 | Claude Code로 refactoring 했더니 훨씬 깔끔해졌어. | 클라우드 코드로 리팩터링 했더니 훨씬 깔끔해졌어. | 66% |
| wk-turbo-632mb-prompt | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | 그 bug는 production에서만 제안이 되어서 debugging이 어려워. | 11% |
| wk-turbo-632mb-prompt | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| wk-turbo-632mb-vocab-en | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you like check whether the Claude Code hooks are running before each comment? | 7% |
| wk-turbo-632mb-vocab-en | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| wk-turbo-632mb-vocab-en | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| wk-turbo-632mb-vocab-en | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| wk-turbo-632mb-vocab-en | mx01 | 오늘 meeting에서 project timeline 얘기했어. | 오늘 미팅에서 프로젝트 타임라인 얘기했어. | 73% |
| wk-turbo-632mb-vocab-en | mx02 | 이거 pull request 올렸으니까 review 좀 부탁해. | 이거 pull request 올렸으니까 리뷰 좀 부탁해. | 21% |
| wk-turbo-632mb-vocab-en | mx03 | 음, Supabase migration은 다음 주에 하는 걸로 하자. | 음... Superbase Migration은 다음 주에 하는 걸로 하자. | 7% |
| wk-turbo-632mb-vocab-en | mx05 | 내일 deadline이라서 오늘 밤에 deploy 해야 돼. | 내일 데드라인이라서 오늘 밤에 deploy해야 돼. | 31% |
| wk-turbo-632mb-vocab-en | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think... I think this part is a little more. | 123% |
| wk-turbo-632mb-vocab-en | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | Bug는 프로덕션에서만 제안이 돼서 디버깅이 어려워. | 61% |
| wk-turbo-632mb-vocab-en | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 Sprint Planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| wk-turbo-632mb-vocab-ko-sentence | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So, honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| wk-turbo-632mb-vocab-ko-sentence | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| wk-turbo-632mb-vocab-ko-sentence | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| wk-turbo-632mb-vocab-ko-sentence | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 그 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 29% |
| wk-turbo-632mb-vocab-ko-sentence | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| wk-turbo-632mb-vocab-ko-sentence | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, I think this is a little more about the part. | 159% |
| wk-turbo-632mb-vocab-ko-sentence | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | 그 bug는 프로덕션에서만 제안이 되어서 디버깅이 어려워. | 64% |
| wk-turbo-632mb-vocab-ko-sentence | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| wk-turbo-632mb-vocab-mixed-ko | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you check whether the Claude Code hooks are running before each comment? | 14% |
| wk-turbo-632mb-vocab-mixed-ko | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So, honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| wk-turbo-632mb-vocab-mixed-ko | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| wk-turbo-632mb-vocab-mixed-ko | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| wk-turbo-632mb-vocab-mixed-ko | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 33% |
| wk-turbo-632mb-vocab-mixed-ko | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| wk-turbo-632mb-vocab-mixed-ko | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, I think this is a little more. | 105% |
| wk-turbo-632mb-vocab-mixed-ko | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | Bug는 production에서만 제안이 돼서 디버깅이 어려워. | 33% |
| wk-turbo-632mb-vocab-mixed-ko | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| wk-turbo-632mb-vocab-mixed | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you check whether the Claude Code hooks are running before each comment? | 14% |
| wk-turbo-632mb-vocab-mixed | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So, honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| wk-turbo-632mb-vocab-mixed | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어. | 7% |
| wk-turbo-632mb-vocab-mixed | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아. | 5% |
| wk-turbo-632mb-vocab-mixed | ko08 | 그, 이제 막 시작한 프로젝트라서 아직 정해진 게 별로 없어요. | 이제 막 시작한 project라서 아직 정해진 게 별로 없어요. | 33% |
| wk-turbo-632mb-vocab-mixed | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아. | 5% |
| wk-turbo-632mb-vocab-mixed | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think, I think this is a little more. | 105% |
| wk-turbo-632mb-vocab-mixed | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | Bug는 production에서만 제안이 돼서 디버깅이 어려워. | 33% |
| wk-turbo-632mb-vocab-mixed | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 sprint planning 때 이 티켓 우선순위 다시 정하자. | 18% |
| wk-turbo-632mb | en07 | I deployed the Supabase migration and updated the environment variables in Vercel. | I deployed the super-based migration and updated the environment variables in Versailles. | 25% |
| wk-turbo-632mb | en08 | Thanks for the quick reply. I'll review the pull request this afternoon and leave comments. | Thanks for the quick reply. I'll review the poll request this afternoon and leave comments. | 6% |
| wk-turbo-632mb | en09 | Can you, like, check whether the Claude Code hooks are running before each commit? | Can you like check whether the Cloud Code hooks are running before each comment? | 14% |
| wk-turbo-632mb | en10 | Honestly, I'm not sure that's the right approach, but let's try it and see what happens. | So honestly, I'm not sure that's the right approach, but let's try it and see what happens. | 5% |
| wk-turbo-632mb | ko01 | 오늘 저녁에 뭐 먹을지 아직 못 정했어. | 오늘 저녁에 뭘 먹을지 아직 못 정했어 | 7% |
| wk-turbo-632mb | ko07 | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 것 같아. | 요즘 날씨가 너무 추워져서 감기 걸리기 쉬운 거 같아 | 5% |
| wk-turbo-632mb | ko09 | 택배가 아직 안 와서 고객센터에 전화해 봐야 할 것 같아. | 택배가 아직 안 와서 고객센터에 전화해 봐야 될 것 같아 | 5% |
| wk-turbo-632mb | mx01 | 오늘 meeting에서 project timeline 얘기했어. | 오늘 미팅에서 프로젝트 타임라인 얘기했어. | 73% |
| wk-turbo-632mb | mx02 | 이거 pull request 올렸으니까 review 좀 부탁해. | 이거 포 리퀘스트 올렸으니까 리뷰 좀 부탁해 | 61% |
| wk-turbo-632mb | mx03 | 음, Supabase migration은 다음 주에 하는 걸로 하자. | 음... Superbase Migration은 다음 주에 하는 걸로 하자. | 7% |
| wk-turbo-632mb | mx05 | 내일 deadline이라서 오늘 밤에 deploy 해야 돼. | 내일 데드라인이라서 오늘 밤에 디플로이해야 돼 | 54% |
| wk-turbo-632mb | mx06 | I think 이 부분은 조금 더 생각해 봐야 할 것 같아. | I think 이 부분을 조금 더 생각해봐야 될 것 같아 | 9% |
| wk-turbo-632mb | mx07 | Claude Code로 refactoring 했더니 훨씬 깔끔해졌어. | 클라우드 코드로 리팩터링 했더니 훨씬 깔끔해졌어 | 66% |
| wk-turbo-632mb | mx08 | 어, 그 bug는 production에서만 재현이 돼서 debugging이 어려워. | 그 버그는 프로덕션에서만 제안이 돼서 디버깅이 어려워 | 67% |
| wk-turbo-632mb | mx10 | 다음 sprint planning 때 이 ticket 우선순위 다시 정하자. | 다음 스프린트 플래닝 때 이 티켓 우선순위 다시 정하자 | 61% |
