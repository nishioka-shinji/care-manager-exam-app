#!/usr/bin/env python3
"""
Linear Task Sync Script
日報から抽出した申し送りタスクを Linear に一括登録します。

使い方:
  1. .env ファイルに LINEAR_API_KEY を設定してください。
  2. 必要に応じて LINEAR_PROJECT_NAME や LINEAR_TEAM_KEY も指定可能です。
  3. 実行:
     python3 scripts/sync_tasks_to_linear.py
     (事前確認: python3 scripts/sync_tasks_to_linear.py --dry-run)
"""

import sys
import os
import json
import urllib.request
import urllib.error

# 日報から抽出した申し送りタスク一覧
# Priority: 0: None, 1: Urgent, 2: High, 3: Medium, 4: Low
TASKS = [
    {
        "title": "全16年度の試験データ取り込みとホーム画面の年度選択カード刷新",
        "priority": 2,  # High
        "description": """## 概要
移植元（Web版 `~/develop/care-manager-exam`）には全16年度分の試験データがありますが、現在は第28回（`assets/data/exam-28.json`）のみとなっています。全16年度分のデータを取り込み、ホーム画面で年度を選択できるように年度カードを刷新します。

## 背景・申し送り
- 2026-09-20 / 2026-09-22 日報申し送り
- PR#1 および PR#3 で一問一答モードと正誤記録の年度スコープ化は完了済み。全16年度のデータ取り込みとホームの年度カード刷新が残課題。

## やること
- [ ] 移植元から 16 年度分の試験データ（`exam-*.json`）を取り込み、`assets/data/` に配置する
- [ ] `assets/data/index.json` を更新し、全年度を認識させる
- [ ] ホーム画面の年度選択UI・年度カードを刷新し、複数年度を切り替えて演習できるようにする
- [ ] 各年度での通し演習・一問一答・履歴更新の動作を確認する
""",
    },
    {
        "title": "画面シェル配線テストの強化（テスト側のシェル書き写し解消）",
        "priority": 3,  # Medium
        "description": """## 概要
結合テスト・ルーティングテスト側で画面シェルを挿しているため、本番の画面シェル配線を外しても全テストがパスしてしまう課題（mainからの持ち越し）を解消します。

## 背景・申し送り
- 2026-09-22 日報「結合テストに本番構造を書き写していた」「統合レビューで同じ穴が main の時点から残っていることが判明」
- 画面シェルの配線（`AppShell` / `RouteObserver` / テーマ等）が外れた場合に確実に回帰を検出できるよう、本番のルーティング・配線を経由するテスト構造へ改修する。

## やること
- [ ] 既存のルーティングテスト（`test/routing_test.dart` 等）がテスト側でシェルを構築している箇所を特定
- [ ] 本番の `App` / `AppShell` 配線を経由してテストを実行する形に修正
- [ ] 配線を外した際にテストが正しく失敗すること（ミューテーション確認）を検証
""",
    },
    {
        "title": "正誤記録マイグレーションの実機・実データ検証",
        "priority": 3,  # Medium
        "description": """## 概要
旧形式（問番号のみをキーとする形式）から年度スコープ形式への正誤記録移行ロジックについて、実機環境または実データを用いた安全性の検証を行います。

## 背景・申し送り
- 2026-09-22 日報「正誤記録の移行そのものは実地で確認していない。debug 版の署名差で既存データが消えるため」
- 単体テストでは旧形式からの移行・冪等性・破損キーの扱いを検証済みだが、実機（本番データ想定）での動作確認が未完了。

## やること
- [ ] 旧形式の正誤データ（`cme:stats`）を保持した状態からアプリアップデートした際のマイグレーション検証手順を策定
- [ ] 実機またはエミュレータにて、旧形式データが新形式（第28回スコープ）へ正しく移行され、復習モードや履歴が壊れないことを確認
""",
    },
    {
        "title": "macOS 環境のセットアップとビルド・動作検証",
        "priority": 4,  # Low
        "description": """## 概要
現在 Xcode 未導入のためスキップされている macOS 版のビルドおよび動作確認を実施します。

## 背景・申し送り
- 2026-09-20 / 2026-09-22 日報「macOS は Xcode 未導入のため未検証」
- CLAUDE.md に「`mise exec -- flutter build macos --debug` は Xcode 未導入（Command Line Tools のみ）のため実行できない。macOS 対応は Android 完走後の独立タスクとして扱う」と明記されている。

## やること
- [ ] macOS 開発環境に Xcode を導入・セットアップ
- [ ] `mise exec -- flutter build macos --debug` のビルドが成功することを確認
- [ ] macOS アプリとして起動し、通し動作・レイアウト崩れ等がないか検証
- [ ] CLAUDE.md の検証コマンド一覧から macOS スキップ制限を解除
""",
    },
    {
        "title": "移植元との細かなUI・仕様差異の追従（本番通しボタン非活性等）",
        "priority": 4,  # Low
        "description": """## 概要
移植元（Web版）との細かなUI・振る舞いの差異を整理し、必要な追従を行います。

## 背景・申し送り
- 2026-09-22 日報「移植元にある『本番通し』ボタンの問数 0 非活性も、今回の変更とは無関係な既存の差異なので触っていない」

## やること
- [ ] ホーム画面の「本番通し」ボタン等で、対象問題数が 0 の場合の非活性制御を移植元に合わせて実装
- [ ] その他、Web版とのUI挙動の差異（あれば）を確認・反映
""",
    },
]


def load_env(file_path=".env"):
    """簡易 .env ローダー"""
    env = {}
    if not os.path.exists(file_path):
        return env
    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip("'\"")
    return env


def execute_graphql(api_key, query, variables=None):
    """Linear GraphQL API を実行"""
    url = "https://api.linear.app/graphql"
    payload = {"query": query, "variables": variables or {}}
    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": api_key,
        },
    )

    try:
        with urllib.request.urlopen(req) as res:
            res_body = res.read().decode("utf-8")
            result = json.loads(res_body)
            if "errors" in result:
                print(f"GraphQL エラー: {result['errors']}", file=sys.stderr)
                return None
            return result.get("data")
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        print(f"HTTPエラー {e.code}: {error_body}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"通信エラー: {e}", file=sys.stderr)
        return None


def get_or_create_project(api_key, team_id, project_name):
    """プロジェクト名から既存プロジェクトを検索、なければ新規作成"""
    if not project_name:
        return None

    # 既存プロジェクト検索
    data = execute_graphql(
        api_key,
        """
        query GetProjects {
            projects {
                nodes {
                    id
                    name
                }
            }
        }
        """,
    )
    if data and "projects" in data:
        for p in data["projects"]["nodes"]:
            if p["name"].strip().lower() == project_name.strip().lower():
                print(f"既存プロジェクトを使用: {p['name']}")
                return p["id"]

    # プロジェクト作成
    print(f"新規プロジェクトを作成します: {project_name}")
    res = execute_graphql(
        api_key,
        """
        mutation CreateProject($input: ProjectCreateInput!) {
            projectCreate(input: $input) {
                success
                project {
                    id
                    name
                }
            }
        }
        """,
        {"input": {"name": project_name, "teamIds": [team_id]}},
    )
    if res and res.get("projectCreate", {}).get("success"):
        return res["projectCreate"]["project"]["id"]
    return None


def main():
    dry_run = "--dry-run" in sys.argv

    # プロジェクトルート基準で .env を探す
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    env_path = os.path.join(project_root, ".env")

    env = load_env(env_path)
    api_key = os.environ.get("LINEAR_API_KEY") or env.get("LINEAR_API_KEY")
    team_key = os.environ.get("LINEAR_TEAM_KEY") or env.get("LINEAR_TEAM_KEY")
    project_name = os.environ.get("LINEAR_PROJECT_NAME") or env.get("LINEAR_PROJECT_NAME")

    if dry_run:
        print("=== DRY RUN モード（Linear への登録は行いません） ===")
        print(f"登録予定タスク数: {len(TASKS)} 件\n")
        for i, task in enumerate(TASKS, 1):
            p_map = {1: "Urgent", 2: "High", 3: "Medium", 4: "Low"}
            print(f"[{i}] [{p_map.get(task['priority'], 'Normal')}] {task['title']}")
        print("\nAPIキーを設定して `--dry-run` なしで実行すると Linear に登録されます。")
        return

    if not api_key:
        print("エラー: LINEAR_API_KEY が見つかりません。", file=sys.stderr)
        print(f"ファイル `{env_path}` に LINEAR_API_KEY=lin_api_... を設定してください。", file=sys.stderr)
        sys.exit(1)

    print("Linear に接続中...")
    # チーム一覧取得
    teams_data = execute_graphql(
        api_key,
        """
        query GetTeams {
            teams {
                nodes {
                    id
                    name
                    key
                }
            }
        }
        """,
    )

    if not teams_data or "teams" not in teams_data:
        print("エラー: チーム一覧の取得に失敗しました。APIキーを確認してください。", file=sys.stderr)
        sys.exit(1)

    teams = teams_data["teams"]["nodes"]
    if not teams:
        print("エラー: アカウント内にチームが見つかりません。Linear上でチームを作成してください。", file=sys.stderr)
        sys.exit(1)

    target_team = None
    if team_key:
        for t in teams:
            if t["key"].upper() == team_key.upper() or t["name"].lower() == team_key.lower():
                target_team = t
                break
        if not target_team:
            print(f"警告: 指定されたチームキー '{team_key}' が見つかりませんでした。先頭のチームを使用します。", file=sys.stderr)

    if not target_team:
        target_team = teams[0]
        print(f"対象チーム: {target_team['name']} ({target_team['key']})")
    else:
        print(f"対象チーム: {target_team['name']} ({target_team['key']})")

    # プロジェクトの取得または作成
    project_id = None
    if project_name:
        project_id = get_or_create_project(api_key, target_team["id"], project_name)

    # 既存 Issue のタイトルを取得して重複登録を防止
    existing_titles = set()
    issues_data = execute_graphql(
        api_key,
        """
        query GetIssues($teamId: String!) {
            team(id: $teamId) {
                issues(first: 100) {
                    nodes {
                        title
                    }
                }
            }
        }
        """,
        {"teamId": target_team["id"]},
    )
    if issues_data and issues_data.get("team"):
        for issue_node in issues_data["team"]["issues"]["nodes"]:
            existing_titles.add(issue_node["title"].strip())

    # タスク登録
    print(f"\n合計 {len(TASKS)} 件のタスクを登録します...\n")

    create_mutation = """
    mutation CreateIssue($input: IssueCreateInput!) {
        issueCreate(input: $input) {
            success
            issue {
                id
                identifier
                title
                url
            }
        }
    }
    """

    created_count = 0
    skipped_count = 0
    for task in TASKS:
        if task["title"].strip() in existing_titles:
            print(f"⊘ スキップ（登録済み）: {task['title']}")
            skipped_count += 1
            continue

        input_data = {
            "teamId": target_team["id"],
            "title": task["title"],
            "description": task["description"],
            "priority": task["priority"],
        }
        if project_id:
            input_data["projectId"] = project_id

        variables = {"input": input_data}
        res = execute_graphql(api_key, create_mutation, variables)
        if res and res.get("issueCreate", {}).get("success"):
            issue = res["issueCreate"]["issue"]
            print(f"✓ 作成完了: [{issue['identifier']}] {issue['title']}")
            print(f"  URL: {issue['url']}")
            created_count += 1
        else:
            print(f"✗ 失敗: {task['title']}", file=sys.stderr)

    print(f"\n完了: {created_count} 件作成, {skipped_count} 件スキップ / 全 {len(TASKS)} 件")


if __name__ == "__main__":
    main()
