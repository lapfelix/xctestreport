import Foundation

let sharedStyles = """
    body {
        font-family: -apple-system, BlinkMacSystemFont, "San Francisco", "Helvetica Neue", Helvetica, Arial, sans-serif;
        color: #333;
        margin: 20px;
        background: #F9F9F9;
    }

    h1, h2, h3 {
        font-weight: 600;
        color: #000;
    }

    h2 {
        padding: 8px 12px;
        border-radius: 6px 6px 0 0;
        background: lightgrey;
        margin-bottom: 0px;
        transition: border-radius 0.2s;
    }

    body.test-detail-page {
        margin: 0;
        padding: 0;
        height: 100dvh;
        min-height: 100vh;
        overflow: hidden;
    }

    .test-detail-shell {
        box-sizing: border-box;
        height: 100%;
        display: grid;
        grid-template-rows: auto auto auto minmax(0, 1fr);
        gap: 8px;
        padding: 10px;
    }

    .test-header-compact {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        min-height: 0;
    }

    .test-title-row {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 6px 10px;
        min-width: 0;
    }

    .test-title-compact {
        margin: 0;
        font-size: 1rem;
        line-height: 1.2;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: min(70vw, 900px);
    }

    .test-duration-pill {
        display: inline-flex;
        align-items: center;
        font-size: 0.82rem;
        line-height: 1;
        border-radius: 999px;
        background: #EFF4FF;
        border: 1px solid #D7E1FF;
        color: #2C4D89;
        padding: 4px 8px;
    }

    .test-back-link {
        font-size: 0.85rem;
        white-space: nowrap;
    }

    .test-error-box {
        border: 1px solid #E6C9C9;
        border-radius: 8px;
        background: #FFF6F6;
        color: #8A1E1E;
        padding: 8px 10px;
        max-height: 88px;
        overflow: auto;
        min-height: 0;
    }

    .test-error-box pre {
        margin: 0;
        white-space: pre-wrap;
        word-break: break-word;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        font-size: 0.82rem;
        line-height: 1.35;
    }

    .test-meta-details {
        border: 1px solid #DBE1EC;
        border-radius: 8px;
        background: #FFFFFF;
        overflow: hidden;
        min-height: 0;
        position: relative;
        z-index: 30;
    }

    .test-meta-details[open] {
        overflow: visible;
    }

    .test-meta-details > summary {
        cursor: pointer;
        list-style: none;
        padding: 8px 10px;
        font-size: 0.88rem;
        font-weight: 600;
        border-bottom: 1px solid transparent;
        display: flex;
        align-items: center;
        gap: 8px;
        border-radius: 8px;
        user-select: none;
        width: 100%;
        box-sizing: border-box;
    }

    .test-meta-details > summary::before {
        content: "\\25B6";
        font-size: 0.72rem;
        color: #4D5C77;
    }

    .test-meta-details > summary::-webkit-details-marker {
        display: none;
    }

    .test-meta-details[open] > summary {
        background: #F8FAFD;
        border-bottom-color: transparent;
    }

    .test-meta-details[open] > summary::before {
        content: "\\25BC";
    }

    .test-meta-content {
        display: none;
    }

    .test-meta-details[open] > .test-meta-content {
        display: block;
        position: absolute;
        top: calc(100% + 6px);
        left: 0;
        right: 0;
        padding: 10px 12px;
        max-height: min(44vh, 460px);
        overflow: auto;
        border: 1px solid #D6DEEC;
        border-radius: 8px;
        background: #FFFFFF;
        box-shadow: 0 10px 26px rgba(21, 34, 57, 0.18);
    }

    .test-meta-content h3 {
        margin: 10px 0 6px;
        font-size: 0.9rem;
    }

    .test-main-content {
        min-height: 0;
        display: flex;
        flex-direction: column;
    }

    .container {
        max-width: 1200px;
        margin: 0 auto;
        padding: 20px;
    }

    .summary {
        margin-bottom: 20px;
    }

    .header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 20px;
    }

    .summary-stats {
        font-size: 1.2em;
        margin: 20px 0;
        padding: 15px;
        background: white;
        border-radius: 8px;
        box-shadow: 0 1px 3px rgba(30, 26, 26, 0.1);
        display: flex;
        flex-direction: column;
        gap: 20px;
    }

    .stat-number {
        font-size: 1.3em;
        font-weight: 600;
        font-feature-settings: "tnum";
        font-variant-numeric: tabular-nums;
    }

    .failure, .failed {
        color: #DC3545;
    }

    .success, .passed {
        color: #28A745;
    }

    .failed-number {
        color: #DC3545;
    }

    .passed-number {
        color: #28A745;
    }

    .skipped-number {
        color: #6c757d;
    }

    .details {
        margin-top: 20px;
    }

    table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 20px;
        background: #FFF;
        border: 1px solid #DDD;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        table-layout: fixed;
    }

    th, td {
        text-align: left;
        padding: 12px;
        border-bottom: 1px solid #EEE;
        word-wrap: break-word;
    }

    th {
        background: #F2F2F2;
        font-weight: 600;
    }

    th:nth-child(1), td:nth-child(1) {
        width: 60%;
    }

    th:nth-child(2), td:nth-child(2) {
        width: 20%;
    }

    th:nth-child(3), td:nth-child(3) {
        width: 20%;
    }

    .test-case {
        margin-bottom: 20px;
        padding: 10px;
        border: 1px solid #ddd;
        border-radius: 4px;
    }

    tr.failed {
        background-color: #f8d7da;
    }

    .status-badge {
        display: inline-block;
        padding: 4px 8px;
        border-radius: 4px;
        font-size: 12px;
        font-weight: bold;
    }

    .status-failed {
        background-color: #ffebee;
        color: #c62828;
    }

    .status-passed {
        background-color: #e8f5e9;
        color: #2e7d32;
    }

    .error-message {
        color: #c62828;
        margin-top: 10px;
        font-family: monospace;
        white-space: pre-wrap;
    }

    .duration {
        color: #666;
        font-size: 0.9em;
    }

    .screenshot {
        max-width: 100%;
        margin-top: 10px;
    }

    .media-section {
        margin-top: 24px;
    }

    .media-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
        gap: 16px;
    }

    .video-card {
        background: #FFFFFF;
        border: 1px solid #DDD;
        border-radius: 8px;
        padding: 12px;
    }

    .test-video {
        width: 100%;
        border-radius: 6px;
        background: #000;
    }

    .media-caption {
        margin: 10px 0 0;
        font-size: 0.9em;
        color: #666;
        display: flex;
        justify-content: space-between;
        gap: 8px;
        align-items: center;
    }

    .attachment-failure {
        font-size: 0.8em;
        color: #c62828;
        background-color: #ffebee;
        border-radius: 3px;
        padding: 2px 6px;
        white-space: nowrap;
    }

    .timeline-video-section {
        margin-top: 24px;
        padding: 12px;
        border: 1px solid #DCE3EF;
        border-radius: 12px;
        background: #F3F6FB;
    }

    .test-detail-page .timeline-video-section {
        margin-top: 0;
        padding: 10px;
        height: 100%;
        min-height: 0;
        display: grid;
        grid-template-rows: minmax(0, 1fr) auto;
        gap: 10px;
    }

    .timeline-video-layout {
        display: grid;
        grid-template-columns: minmax(420px, 56%) minmax(0, 1fr);
        gap: 12px;
        align-items: start;
    }

    .test-detail-page .timeline-video-layout {
        height: 100%;
        min-height: 0;
        align-items: stretch;
    }

    .timeline-panel,
    .video-panel {
        background: #FFFFFF;
        border: 1px solid #DEE4EE;
        border-radius: 10px;
        padding: 10px;
        box-shadow: 0 1px 2px rgba(20, 28, 45, 0.04);
    }

    .test-detail-page .timeline-panel,
    .test-detail-page .video-panel {
        min-height: 0;
        display: flex;
        flex-direction: column;
    }

    .timeline-panel h3,
    .video-panel h3 {
        margin-top: 0;
        margin-bottom: 10px;
        font-size: 1.05em;
    }

    .video-panel {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 8px;
    }

    .timeline-current {
        margin-bottom: 8px;
        border-radius: 8px;
        border: 1px solid #D9E2F1;
        background: #F7FAFF;
        color: #22314E;
        font-size: 0.9em;
        font-weight: 500;
        line-height: 1.25;
        text-align: center;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 2.5em;
        max-height: 4.8em;
        overflow: hidden;
        padding: 8px 10px;
    }

    .timeline-tree {
        max-height: 62vh;
        overflow: auto;
        border: 1px solid #E5EAF3;
        border-radius: 6px;
        padding: 8px;
        background: #FFF;
    }

    .test-detail-page .timeline-tree {
        flex: 1;
        max-height: none;
        min-height: 0;
    }

    .timeline-tree ul {
        list-style: none;
        margin: 0;
        padding-left: 0;
    }

    .timeline-tree .timeline-root {
        padding-left: 0;
    }

    .timeline-node {
        margin-bottom: 2px;
    }

    .timeline-node summary {
        list-style: none;
        cursor: pointer;
        position: relative;
        padding-left: 0;
    }

    .timeline-node summary::-webkit-details-marker {
        display: none;
    }

    .timeline-event {
        border-radius: 7px;
        padding: 6px 10px;
        cursor: pointer;
        border: 1px solid transparent;
        display: grid;
        grid-template-columns: 14px minmax(0, 1fr) 62px;
        column-gap: 10px;
        align-items: flex-start;
    }

    .timeline-disclosure {
        width: 14px;
        height: 14px;
        margin-top: 1px;
        border-radius: 4px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        color: #6D7890;
        font-size: 0.62rem;
        line-height: 1;
        border: 1px solid transparent;
        background: transparent;
        user-select: none;
    }

    .timeline-disclosure::before {
        content: "";
    }

    .timeline-disclosure.timeline-disclosure-placeholder {
        visibility: hidden;
    }

    .timeline-event.timeline-has-children .timeline-disclosure {
        border-color: #D7DFED;
        background: #F3F7FD;
    }

    .timeline-node > details > summary > .timeline-event.timeline-has-children .timeline-disclosure::before {
        content: "\\25B6";
    }

    .timeline-node > details[open] > summary > .timeline-event.timeline-has-children .timeline-disclosure::before {
        content: "\\25BC";
    }

    .timeline-tree ul > li.timeline-node:nth-child(odd) > .timeline-event,
    .timeline-tree ul > li.timeline-node:nth-child(odd) > details > summary > .timeline-event {
        background: #FCFDFF;
        border-color: #EDF1F7;
    }

    .timeline-tree ul > li.timeline-node:nth-child(even) > .timeline-event,
    .timeline-tree ul > li.timeline-node:nth-child(even) > details > summary > .timeline-event {
        background: #F7FAFF;
        border-color: #E8EDF5;
    }

    .timeline-event:hover {
        background: #F4F7FF;
        border-color: #D7E1FF;
    }

    .timeline-event.timeline-active {
        background: #EAF0FF;
        border-color: #8EB1FF;
    }

    .timeline-tree ul > li.timeline-node > .timeline-event.timeline-failure,
    .timeline-tree ul > li.timeline-node > details > summary > .timeline-event.timeline-failure {
        background: #FDECEE;
        border-color: #F4BCC3;
    }

    .timeline-tree ul > li.timeline-node > .timeline-event.timeline-failure:hover,
    .timeline-tree ul > li.timeline-node > details > summary > .timeline-event.timeline-failure:hover {
        background: #FBE2E6;
        border-color: #EDA8B1;
    }

    .timeline-tree ul > li.timeline-node > .timeline-event.timeline-failure.timeline-active,
    .timeline-tree ul > li.timeline-node > details > summary > .timeline-event.timeline-failure.timeline-active {
        background: #F8D3D9;
        border-color: #DF7F8D;
    }

    .timeline-event.timeline-failure .timeline-title {
        color: #9f1f2f;
    }

    .timeline-time {
        color: #666;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        font-size: 0.83em;
        font-variant-numeric: tabular-nums;
        min-width: 62px;
        text-align: right;
        justify-self: end;
        position: relative;
        padding-left: 12px;
        margin-top: 1px;
    }

    .timeline-event.timeline-interaction .timeline-time::before {
        content: "";
        position: absolute;
        left: 2px;
        top: 50%;
        width: 6px;
        height: 6px;
        border-radius: 999px;
        transform: translateY(-50%);
        background: #3485ff;
        box-shadow: 0 0 0 2px rgba(52, 133, 255, 0.18);
    }

    .timeline-title {
        min-width: 0;
        word-break: break-word;
        line-height: 1.35;
        padding-left: calc(var(--timeline-depth, 0) * 14px);
    }

    .timeline-attachments {
        margin: 4px 0 8px;
        padding-left: calc(24px + (var(--timeline-depth, 0) * 14px));
    }

    .timeline-attachment {
        font-size: 0.86em;
        color: #666;
        margin: 2px 0;
    }

    .timeline-controls {
        margin-top: 14px;
        display: grid;
        gap: 8px;
        border: 1px solid #DBE1EC;
        border-radius: 9px;
        background: #FFFFFF;
        padding: 8px 10px;
    }

    .test-detail-page .timeline-controls {
        margin-top: 0;
    }

    .timeline-buttons {
        display: flex;
        justify-content: center;
        gap: 8px;
    }

    .timeline-button {
        width: 34px;
        height: 30px;
        padding: 0;
        border-radius: 6px;
        border: 1px solid #CBD5E3;
        background: #FAFAFA;
        cursor: pointer;
        font-size: 0.94em;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        line-height: 1;
    }

    .timeline-button-play {
        width: 40px;
        font-size: 1.05em;
    }

    .timeline-button:hover {
        background: #F0F0F0;
    }

    .timeline-scrubber {
        width: 100%;
        accent-color: #2e6bd6;
    }

    .timeline-timebar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        color: #5E6D86;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        font-size: 0.81em;
        font-variant-numeric: tabular-nums;
    }

    .timeline-status {
        font-size: 0.9em;
        color: #555;
    }

    .stack-trace {
        margin-top: 8px;
        padding: 10px 12px;
        border-radius: 8px;
        border: 1px solid #DBE1EC;
        background: #F8FAFD;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        font-size: 0.82em;
        line-height: 1.35;
        overflow: auto;
        white-space: pre;
    }

    .video-selector {
        width: min(100%, 390px);
        margin-bottom: 6px;
        padding: 6px 8px;
        border-radius: 6px;
        border: 1px solid #CBD5E3;
        background: #FFF;
        font-size: 0.92em;
    }

    .timeline-video-card {
        width: min(100%, 390px);
        margin: 0 auto;
    }

    .test-detail-page .timeline-video-card {
        width: min(100%, 390px, calc((100dvh - 380px) * 9 / 16));
    }

    .timeline-video-frame {
        position: relative;
        width: 100%;
        aspect-ratio: 9 / 16;
        border-radius: 8px;
        overflow: hidden;
        border: 1px solid #D5DCE7;
        background: #0a0a0a;
    }

    .timeline-video {
        width: 100%;
        height: 100%;
        background: #000;
        object-fit: contain;
    }

    .touch-overlay-layer {
        position: absolute;
        inset: 0;
        pointer-events: none;
        overflow: hidden;
    }

    .touch-indicator {
        position: absolute;
        width: 24px;
        height: 24px;
        border-radius: 999px;
        border: 2px solid rgba(255, 255, 255, 0.95);
        background: rgba(255, 255, 255, 0.32);
        box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.28), 0 6px 18px rgba(0, 0, 0, 0.25);
        transform: translate(-50%, -50%) scale(0.9);
        opacity: 0;
        transition: opacity 120ms linear, transform 120ms linear;
        will-change: transform, opacity, left, top;
    }

    .new-failure {
        color: #856404;
        background-color: #fff3cd;
        padding: 2px 6px;
        border-radius: 3px;
        font-size: 0.9em;
    }

    .fixed {
        color: #155724;
        background-color: #d4edda;
        padding: 2px 6px;
        border-radius: 3px;
        font-size: 0.9em;
    }

    .emoji-status {
        text-decoration: none;
        margin-left: 4px;
    }

    a {
        color: #0077EE;
        text-decoration: none;
    }

    a:hover {
        text-decoration: underline;
    }

    /* Collapsible sections */
    .collapsible {
        display: flex;
        flex-direction: column;
        gap: 4px;
        padding-right: 25px;
        position: relative;
        cursor: pointer;
        user-select: none;
    }

    .collapsible::after {
        content: "\\25BC";
        position: absolute;
        right: 10px;
        top: 50%;
        transform: translateY(-50%);
        font-size: 0.8em;
        transition: transform 0.2s;
    }

    .collapsed::after {
        content: "\\25B6";
    }

    .suite-name {
        font-size: 1.1em;
        font-weight: 600;
        margin-right: 8px;
    }

    .suite-stats {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 4px 8px;
        font-size: 0.9em;
        font-weight: normal;
        color: #666;
        padding-right: 15px;
    }

    .content {
        max-height: 2000px;
        opacity: 1;
        transition: max-height 0.3s ease-in-out, opacity 0.2s ease-in-out;
        overflow: hidden;
    }

    .collapsed + .content {
        max-height: 0;
        opacity: 0;
    }

    .suite {
        margin-bottom: 1px;
    }

    button#toggle-all {
        padding: 8px 16px;
        font-size: 14px;
        font-weight: 500;
        color: #24292e;
        background-color: #fafbfc;
        border: 1px solid rgba(27,31,35,0.15);
        border-radius: 6px;
        box-shadow: 0 1px 0 rgba(27,31,35,0.04);
        cursor: pointer;
        user-select: none;
        transition: all 0.2s ease;
        width: 100%;
    }

    [title] {
        position: relative;
        cursor: help;
    }

    /* Media Queries */
    @media (min-width: 768px) {
        .summary-stats {
            flex-direction: row;
            align-items: center;
            justify-content: space-between;
        }
        
        button#toggle-all {
            width: auto;
            white-space: nowrap;
        }

        .collapsible {
            flex-direction: row;
            align-items: center;
            justify-content: space-between;
        }
        
        .suite-name {
            margin-right: 0;
        }
    }

    @media (max-width: 980px) {
        .timeline-video-layout {
            grid-template-columns: 1fr;
        }

        .timeline-tree,
        .timeline-video-frame {
            max-height: 45vh;
        }

        .video-panel {
            align-items: stretch;
        }

        .test-detail-page .test-detail-shell {
            gap: 6px;
            padding: 8px;
        }

        .test-detail-page .test-header-compact {
            align-items: flex-start;
            flex-direction: column;
        }

        .test-detail-page .test-title-compact {
            max-width: 100%;
        }

        .test-detail-page .timeline-video-layout {
            grid-template-columns: 1fr;
            grid-template-rows: minmax(0, 1fr) auto;
            gap: 10px;
        }

        .test-detail-page .timeline-video-card {
            width: min(100%, 320px);
        }

        .test-detail-page .timeline-video-frame {
            max-height: 36vh;
        }

        .test-detail-page .test-meta-content {
            max-height: 24vh;
        }
    }

    @media (prefers-color-scheme: dark) {
        body {
            background-color: #121212;
            color: #EEEEEE;
        }

        body.test-detail-page {
            background-color: #121212;
        }
        
        h1, h2, h3 {
            color: #FFFFFF;
        }

        h2 {
            background: rgb(59, 59, 59);
        }

        .suite-stats {
            color: #e0e0e0;
        }
        
        .skipped-number {
            color: #a8aaab;
        }

        .summary-stats {
            background: #202020;
        }

        table {
            background: #171717;
        }

        .summary-stats, table {
            background: #171717;
            border-color: #DDD;
        }

        .test-duration-pill {
            background: #1F2B42;
            border-color: #355590;
            color: #CFDAF8;
        }

        .test-error-box {
            background: #2A1D1D;
            border-color: #5A3030;
            color: #FFBABA;
        }

        .test-meta-details {
            background: #171717;
            border-color: #424242;
        }

        .test-meta-details[open] > summary {
            background: #1f1f1f;
            border-bottom-color: transparent;
        }

        .test-meta-details > summary::before {
            color: #C0CCE2;
        }

        .test-meta-details[open] > .test-meta-content {
            background: #171717;
            border-color: #424242;
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.45);
        }

        .video-card {
            background: #171717;
            border-color: #424242;
        }

        .media-caption {
            color: #e0e0e0;
        }

        .attachment-failure {
            background-color: #514116;
            color: #f5d7a1;
        }

        .timeline-panel,
        .video-panel,
        .timeline-tree,
        .video-selector,
        .timeline-controls,
        .timeline-video-section {
            background: #171717;
            border-color: #424242;
            color: #e7e7e7;
        }

        .timeline-current {
            background: #1B2432;
            border-color: #314056;
            color: #D8E5FF;
        }

        .timeline-video-frame {
            border-color: #424242;
            background: #000;
        }

        .timeline-event:hover {
            background: #1f2b42;
            border-color: #355590;
        }

        .timeline-tree ul > li.timeline-node:nth-child(odd) > .timeline-event,
        .timeline-tree ul > li.timeline-node:nth-child(odd) > details > summary > .timeline-event {
            background: #1A1F27;
            border-color: #2A303A;
        }

        .timeline-tree ul > li.timeline-node:nth-child(even) > .timeline-event,
        .timeline-tree ul > li.timeline-node:nth-child(even) > details > summary > .timeline-event {
            background: #202733;
            border-color: #2E3643;
        }

        .timeline-event.timeline-active {
            background: #223c6d;
            border-color: #5f8de8;
        }

        .timeline-tree ul > li.timeline-node > .timeline-event.timeline-failure,
        .timeline-tree ul > li.timeline-node > details > summary > .timeline-event.timeline-failure {
            background: #3E2027;
            border-color: #65404B;
        }

        .timeline-tree ul > li.timeline-node > .timeline-event.timeline-failure:hover,
        .timeline-tree ul > li.timeline-node > details > summary > .timeline-event.timeline-failure:hover {
            background: #4A2630;
            border-color: #7D4B59;
        }

        .timeline-tree ul > li.timeline-node > .timeline-event.timeline-failure.timeline-active,
        .timeline-tree ul > li.timeline-node > details > summary > .timeline-event.timeline-failure.timeline-active {
            background: #5A2C38;
            border-color: #A66A79;
        }

        .timeline-event.timeline-failure .timeline-title {
            color: #ffbcc6;
        }

        .timeline-event.timeline-interaction .timeline-time::before {
            background: #73A7FF;
            box-shadow: 0 0 0 2px rgba(115, 167, 255, 0.25);
        }

        .stack-trace {
            background: #111827;
            border-color: #424242;
            color: #e2e8f0;
        }

        .timeline-time,
        .timeline-attachment,
        .timeline-status,
        .timeline-timebar {
            color: #cfd5de;
        }

        .timeline-disclosure {
            color: #cfd5de;
        }

        .timeline-event.timeline-has-children .timeline-disclosure {
            background: #253043;
            border-color: #4B5E80;
        }

        .timeline-button {
            color: #e7e7e7;
            background-color: #4a4a4a;
            border: 1px solid rgba(255, 255, 255, 0.15);
        }

        .timeline-button:hover {
            background-color: #575757;
        }
        
        th {
            background: #242424;
        }

        th, td {
            border-bottom: 1px solid #424242;
        }

        button#toggle-all {
            color: #e7e7e7;
            background-color: #4a4a4a;
            border: 1px solid rgba(255, 255, 255, 0.15);
        }
        
        a {
            color: #599efc;
        }
        
        .failed {
            color: #ff867c;
        }
        
        .passed {
            color: #2eaa48;
        }
        
        tr.failed {
            background-color: #241414;
        }
        
        .new-failure {
            background-color: #514116;
            color: #f5d7a1;
        }
        
        .fixed {
            background-color: #1b3d2f;
            color: #b1e3bf;
        }
    }
    """
