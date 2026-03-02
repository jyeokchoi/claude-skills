#!/usr/bin/env node

/**
 * PreCompact hook: 컴팩션 직전에 활성 워크로그의 핵심 컨텍스트를 저장하고
 * 타임라인에 compaction 마커를 삽입한다.
 */

import { readFile, writeFile, access, readdir } from 'node:fs/promises';
import { join, relative } from 'node:path';

const safe = (fn) => fn().catch(() => null);

const readStdin = () =>
  new Promise((resolve) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => (data += chunk));
    process.stdin.on('end', () => resolve(data));
    setTimeout(() => resolve(data), 9000);
  });

const extractFrontmatterField = (content, field) => {
  const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (!fmMatch) return null;
  const re = new RegExp(`^${field}:\\s*(.+)$`, 'm');
  const m = fmMatch[1].match(re);
  return m ? m[1].trim() : null;
};

const extractSection = (content, startMarker, endMarker) => {
  const startIdx = content.indexOf(startMarker);
  if (startIdx === -1) return null;
  const afterStart = startIdx + startMarker.length;
  const endIdx = endMarker ? content.indexOf(endMarker, afterStart) : -1;
  return endIdx === -1
    ? content.slice(afterStart).trim()
    : content.slice(afterStart, endIdx).trim();
};

const extractGoal = (content) => {
  const match = content.match(/^## Goal\b/m);
  if (!match) return null;
  const start = match.index + match[0].length;
  const nextSection = content.slice(start).search(/^## /m);
  return nextSection === -1
    ? content.slice(start).trim()
    : content.slice(start, start + nextSection).trim();
};

const extractCompletionCriteria = (content) => {
  const match = content.match(/^## Completion [Cc]riteria\b/m);
  if (!match) return null;
  const start = match.index + match[0].length;
  const nextSection = content.slice(start).search(/^## /m);
  return nextSection === -1
    ? content.slice(start).trim()
    : content.slice(start, start + nextSection).trim();
};

const timestamp = () => {
  const now = new Date();
  return now.toLocaleString('en-US', {
    timeZone: 'Asia/Seoul',
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).replace(/(\d+)\/(\d+)\/(\d+),\s*/, '$3-$1-$2 ');
};

const findWorklogDir = async (cwd) => {
  // 1. .active 파일 확인
  const activePath = join(cwd, '.claude', 'worklogs', '.active');
  const activeContent = await safe(() => readFile(activePath, 'utf8'));
  if (activeContent) {
    const dir = activeContent.trim();
    const absDir = dir.startsWith('/') ? dir : join(cwd, '.claude', 'worklogs', dir);
    const wlPath = join(absDir, 'worklog.md');
    try {
      await access(wlPath);
      return absDir;
    } catch { /* fallthrough */ }
  }

  // 2. readdir로 워크로그 검색 (Node <22 호환)
  const worklogsBase = join(cwd, '.claude', 'worklogs');
  try {
    const dirs = await readdir(worklogsBase, { withFileTypes: true });
    const matches = [];
    for (const d of dirs) {
      if (!d.isDirectory() || d.name.startsWith('.')) continue;
      const wlPath = join(worklogsBase, d.name, 'worklog.md');
      try {
        await access(wlPath);
        matches.push(join(worklogsBase, d.name));
      } catch { /* skip */ }
    }
    if (matches.length === 1) return matches[0];
  } catch { /* no worklogs dir */ }

  return null;
};

const readVworkState = async (cwd, sessionId) => {
  const paths = [
    sessionId && join(cwd, '.omc', 'state', 'sessions', sessionId, 'vwork-state.json'),
    join(cwd, '.omc', 'state', 'vwork-state.json'),
  ].filter(Boolean);

  for (const p of paths) {
    const content = await safe(() => readFile(p, 'utf8'));
    if (content) {
      try { return JSON.parse(content); } catch { /* ignore */ }
    }
  }
  return null;
};

const main = async () => {
  try {
    const raw = await readStdin();
    const input = JSON.parse(raw || '{}');
    const cwd = input.cwd || process.cwd();
    const trigger = input.trigger || 'auto';
    const sessionId = input.session_id || null;

    // 워크로그 탐색
    const worklogDir = await findWorklogDir(cwd);
    if (!worklogDir) {
      process.stdout.write(JSON.stringify({ continue: true, suppressOutput: true }));
      return;
    }

    const worklogPath = join(worklogDir, 'worklog.md');
    const content = await readFile(worklogPath, 'utf8');

    // 핵심 정보 추출
    const phase = extractFrontmatterField(content, 'phase');
    const dashboard = extractSection(
      content,
      '<!-- WORKLOG:DASHBOARD:START -->',
      '<!-- WORKLOG:DASHBOARD:END -->'
    );
    const goal = extractGoal(content);
    const criteria = extractCompletionCriteria(content);

    // vwork state
    const vworkState = await readVworkState(cwd, sessionId);

    // 컨텍스트 JSON 저장
    const relWorklogPath = relative(cwd, worklogPath);
    const contextData = {
      timestamp: new Date().toISOString(),
      trigger,
      worklog_path: relWorklogPath,
      phase,
      dashboard,
      goal,
      completion_criteria: criteria,
      vwork: vworkState
        ? {
            mode: vworkState.mode || null,
            current_phase: vworkState.current_phase || null,
            team_name: vworkState.team_name || null,
            spawned_agents: vworkState.spawned_agents || null,
            feedback_iterations: vworkState.feedback_iterations || null,
          }
        : null,
    };

    const contextPath = join(cwd, '.claude', 'compaction-context.json');
    await writeFile(contextPath, JSON.stringify(contextData, null, 2), 'utf8');

    // 타임라인에 compaction 마커 삽입
    const marker = '<!-- WORKLOG:TIMELINE:INSERT:HERE -->';
    const markerIdx = content.indexOf(marker);
    if (markerIdx !== -1) {
      const ts = timestamp();
      const entry = [
        '',
        `### ${ts} (context compaction)`,
        `- **Event**: Context compaction (${trigger})`,
        `- **Phase**: ${phase || 'unknown'}`,
        `- **Context saved**: \`.claude/compaction-context.json\``,
        '',
      ].join('\n');
      const insertPos = markerIdx + marker.length;
      const updated = content.slice(0, insertPos) + '\n' + entry + content.slice(insertPos);
      await writeFile(worklogPath, updated, 'utf8');
    }

    // systemMessage 출력
    const systemMessage = [
      '<worklog-context>',
      `[Compaction Recovery] Worklog context saved before compaction.`,
      `Phase: ${phase || 'unknown'}`,
      dashboard ? `Dashboard:\n${dashboard}` : null,
      goal ? `Goal: ${goal}` : null,
      `Worklog: ${relWorklogPath}`,
      '</worklog-context>',
    ]
      .filter(Boolean)
      .join('\n');

    process.stdout.write(JSON.stringify({ continue: true, systemMessage }));
  } catch {
    process.stdout.write(JSON.stringify({ continue: true, suppressOutput: true }));
  }
};

main();
