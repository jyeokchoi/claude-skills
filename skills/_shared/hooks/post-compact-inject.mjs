#!/usr/bin/env node

/**
 * SessionStart(compact) hook: 컴팩션 완료 후 저장된 워크로그 컨텍스트를
 * systemMessage로 재주입한다.
 */

import { readFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';

const safe = (fn) => fn().catch(() => null);

const readStdin = () =>
  new Promise((resolve) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => (data += chunk));
    process.stdin.on('end', () => resolve(data));
    setTimeout(() => resolve(data), 4000);
  });

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

const extractFrontmatterField = (content, field) => {
  const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (!fmMatch) return null;
  const re = new RegExp(`^${field}:\\s*(.+)$`, 'm');
  const m = fmMatch[1].match(re);
  return m ? m[1].trim() : null;
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
    const sessionId = input.session_id || null;

    // compaction-context.json 읽기
    const contextPath = join(cwd, '.claude', 'compaction-context.json');
    const contextRaw = await safe(() => readFile(contextPath, 'utf8'));
    if (!contextRaw) {
      // compaction이 아닌 일반 재개
      process.stdout.write(JSON.stringify({ continue: true }));
      return;
    }

    const ctx = JSON.parse(contextRaw);

    // 컨텍스트 파일 삭제 (stale data 방지 — 다음 세션에서 오인 차단)
    await safe(() => unlink(contextPath));

    // 워크로그 fresh read
    const worklogPath = join(cwd, ctx.worklog_path);
    const worklogContent = await safe(() => readFile(worklogPath, 'utf8'));

    let dashboard = ctx.dashboard;
    let goal = ctx.goal;
    let criteria = ctx.completion_criteria;
    let phase = ctx.phase;

    if (worklogContent) {
      const freshDashboard = extractSection(
        worklogContent,
        '<!-- WORKLOG:DASHBOARD:START -->',
        '<!-- WORKLOG:DASHBOARD:END -->'
      );
      if (freshDashboard) dashboard = freshDashboard;

      const freshGoal = extractGoal(worklogContent);
      if (freshGoal) goal = freshGoal;

      const freshCriteria = extractCompletionCriteria(worklogContent);
      if (freshCriteria) criteria = freshCriteria;

      const freshPhase = extractFrontmatterField(worklogContent, 'phase');
      if (freshPhase) phase = freshPhase;
    }

    // vwork state fresh read
    const vworkState = await readVworkState(cwd, sessionId);
    const mode = vworkState?.mode || ctx.vwork?.mode || 'unknown';

    // systemMessage 포맷팅
    const parts = [
      '<worklog-context>',
      `[Active Worklog] ${ctx.worklog_path}`,
      `Phase: ${phase || 'unknown'} | Mode: ${mode}`,
      '',
      '## Dashboard',
      dashboard || '(not available)',
      '',
      '## Goal',
      goal || '(not available)',
      '',
      '## Completion Criteria',
      criteria || '(not available)',
      '',
      '[vwork 복구 지침]',
      '- state_read(mode="vwork")로 전체 변수 복구',
      '- SKILL.md의 절대규칙 + 현재 phase 섹션 재읽기',
      '- 팀 생존 확인 → phase 실행 재개',
      '- 오케스트레이터는 직접 코드 수정 금지, SendMessage로 위임만',
      '</worklog-context>',
    ];

    const systemMessage = parts.join('\n');

    process.stdout.write(JSON.stringify({ continue: true, systemMessage }));
  } catch {
    process.stdout.write(JSON.stringify({ continue: true }));
  }
};

main();
