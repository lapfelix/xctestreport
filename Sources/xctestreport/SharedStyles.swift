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
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
        align-items: center;
        gap: 10px;
        min-height: 0;
    }

    .test-title-group {
        min-width: 0;
        justify-self: center;
        text-align: center;
        display: grid;
        gap: 2px;
    }

    .test-title-row {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        justify-content: center;
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
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 0.82rem;
        white-space: nowrap;
        color: #334155;
        border: 1px solid #D4DEED;
        background: #F6F9FF;
        border-radius: 999px;
        padding: 5px 10px;
        justify-self: start;
        width: fit-content;
    }

    .test-back-link svg {
        width: 14px;
        height: 14px;
    }

    .test-header-spacer {
        justify-self: end;
    }

    .test-subtitle {
        color: #66758D;
        font-size: 0.76rem;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: min(70vw, 980px);
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
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        gap: 12px;
        align-items: start;
    }

    .timeline-video-layout.timeline-layout-single {
        grid-template-columns: minmax(0, 1fr);
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

    .test-detail-page .timeline-panel {
        min-height: 0;
        display: flex;
        flex-direction: column;
    }

    .test-detail-page .video-panel {
        min-height: 0;
    }

    .timeline-panel-stack {
        min-height: 0;
        display: flex;
        flex-direction: column;
        gap: 8px;
    }

    .timeline-run-selector {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 0.8rem;
        color: #334155;
        padding: 2px 2px 0;
    }

    .timeline-run-selector label {
        font-weight: 600;
    }

    .timeline-run-select {
        min-width: 120px;
        border: 1px solid #CBD5E3;
        border-radius: 7px;
        background: #FFFFFF;
        color: #1E293B;
        font-size: 0.8rem;
        padding: 4px 8px;
    }

    .timeline-panel h3,
    .video-panel h3 {
        margin-top: 0;
        margin-bottom: 10px;
        font-size: 1.05em;
    }

    .video-panel {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        align-items: stretch;
        gap: 8px;
    }

    .video-media-column {
        min-width: 0;
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

    .timeline-tree-actions {
        margin-top: 8px;
        display: flex;
        justify-content: flex-end;
        gap: 8px;
    }

    .timeline-tree-action-btn {
        border: 1px solid #CBD5E3;
        background: #FAFAFA;
        color: #334155;
        border-radius: 6px;
        padding: 4px 9px;
        font-size: 0.78rem;
        line-height: 1;
        cursor: pointer;
    }

    .timeline-tree-action-btn:hover {
        background: #F0F3F8;
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
        padding: 6px 10px 6px calc(10px + (var(--timeline-depth, 0) * 14px));
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
        box-shadow: inset 0 0 0 1px rgba(88, 130, 222, 0.3);
    }

    .timeline-event.timeline-active .timeline-title,
    .timeline-event.timeline-active .timeline-time,
    .timeline-event.timeline-active .timeline-disclosure {
        color: #1B3D75;
    }

    .timeline-event.timeline-context-active:not(.timeline-active) {
        background: #F1F6FF;
        border-color: #C8D9FF;
    }

    .timeline-event.timeline-active-proxy:not(.timeline-active) {
        background: #E4EEFF;
        border-color: #7EA4F2;
        box-shadow: inset 0 0 0 1px rgba(88, 130, 222, 0.45);
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

    .timeline-tree ul > li.timeline-node > .timeline-event.timeline-failure.timeline-active-proxy:not(.timeline-active),
    .timeline-tree ul > li.timeline-node > details > summary > .timeline-event.timeline-failure.timeline-active-proxy:not(.timeline-active) {
        background: #F6DDE2;
        border-color: #D88B96;
        box-shadow: inset 0 0 0 1px rgba(204, 95, 111, 0.35);
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
        padding-left: 20px;
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

    .timeline-event.timeline-hierarchy .timeline-time::after {
        content: "";
        position: absolute;
        left: 11px;
        top: 50%;
        width: 6px;
        height: 6px;
        border-radius: 999px;
        transform: translateY(-50%);
        background: #AF52DE;
        box-shadow: 0 0 0 2px rgba(175, 82, 222, 0.2);
    }

    .timeline-title {
        min-width: 0;
        word-break: break-word;
        line-height: 1.35;
        white-space: pre-line;
    }

    .timeline-attachments {
        margin: 4px 0 8px;
        padding-left: calc(24px + (var(--timeline-depth, 0) * 14px));
        display: grid;
        gap: 5px;
    }

    .timeline-attachment {
        font-size: 0.83em;
        color: #666;
        margin: 0;
        list-style: none;
    }

    .timeline-attachment-link {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        max-width: 100%;
        border: 1px solid #DFE6F3;
        border-radius: 7px;
        background: #F8FAFE;
        color: #2E3F5A;
        padding: 5px 8px;
        text-decoration: none;
        line-height: 1.25;
    }

    .timeline-attachment-link:hover {
        border-color: #C4D3EE;
        background: #F0F5FF;
        text-decoration: none;
    }

    .timeline-attachment-icon {
        flex: 0 0 auto;
        min-width: 28px;
        text-align: center;
        border-radius: 999px;
        border: 1px solid #CBD7EA;
        background: #EEF3FC;
        color: #3A4E72;
        font-size: 0.66rem;
        font-weight: 700;
        letter-spacing: 0.02em;
        padding: 1px 6px;
    }

    .timeline-attachment-label {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .timeline-attachment-inline {
        margin-top: 6px;
        border: 1px solid #D7E0EE;
        border-radius: 7px;
        background: #F3F7FE;
        max-height: 190px;
        overflow: auto;
    }

    .timeline-attachment-inline pre {
        margin: 0;
        padding: 8px 9px;
        white-space: pre-wrap;
        word-break: break-word;
        line-height: 1.35;
        font-size: 0.74rem;
        color: #2E3F5A;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
    }

    .attachment-preview-modal[hidden] {
        display: none;
    }

    .attachment-preview-modal {
        position: fixed;
        inset: 0;
        z-index: 1200;
        display: grid;
        place-items: center;
    }

    .attachment-preview-backdrop {
        position: absolute;
        inset: 0;
        background: rgba(7, 13, 26, 0.6);
    }

    .attachment-preview-dialog {
        position: relative;
        width: min(92vw, 1040px);
        max-height: 88vh;
        border-radius: 12px;
        border: 1px solid #CFDBEF;
        background: #FFFFFF;
        box-shadow: 0 20px 44px rgba(15, 30, 53, 0.3);
        display: grid;
        grid-template-rows: auto minmax(0, 1fr);
        overflow: hidden;
    }

    .attachment-preview-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        padding: 10px 12px;
        border-bottom: 1px solid #E2E9F5;
        background: #F6F9FF;
    }

    .attachment-preview-title {
        font-size: 0.9rem;
        font-weight: 600;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        color: #1E2D46;
    }

    .attachment-preview-actions {
        display: inline-flex;
        align-items: center;
        gap: 8px;
    }

    .attachment-preview-open {
        font-size: 0.8rem;
        border: 1px solid #CBD7EA;
        border-radius: 6px;
        padding: 4px 8px;
        background: #FFFFFF;
        color: #2A4D86;
        text-decoration: none;
    }

    .attachment-preview-close {
        border: 1px solid #CBD7EA;
        border-radius: 6px;
        padding: 4px 8px;
        background: #FFFFFF;
        color: #334155;
        font-size: 0.8rem;
        cursor: pointer;
    }

    .attachment-preview-body {
        min-height: 0;
        background: #FBFDFF;
        display: grid;
    }

    .attachment-preview-image,
    .attachment-preview-video,
    .attachment-preview-frame,
    .attachment-preview-empty {
        display: none;
        width: 100%;
        height: 100%;
        min-height: 320px;
    }

    .attachment-preview-image {
        object-fit: contain;
        background: #0F172A;
    }

    .attachment-preview-video {
        background: #000;
    }

    .attachment-preview-frame {
        border: 0;
        background: #FFF;
    }

    .attachment-preview-empty {
        align-items: center;
        justify-content: center;
        text-align: center;
        color: #60708B;
        font-size: 0.9rem;
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
    }

    .timeline-button:hover {
        background: #F0F0F0;
    }

    .timeline-icon {
        width: 16px;
        height: 16px;
        display: block;
        fill: currentColor;
    }

    .timeline-button-play .timeline-icon {
        width: 17px;
        height: 17px;
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
        padding: 6px 8px;
        border-radius: 6px;
        border: 1px solid #CBD5E3;
        background: #FFF;
        font-size: 0.92em;
    }

    .timeline-video-card {
        width: min(100%, 460px, calc((100dvh - 260px) * var(--media-aspect, 9 / 16)));
        margin: 0 auto;
    }

    .test-detail-page .timeline-video-card {
        width: min(100%, calc((100dvh - 280px) * var(--media-aspect, 9 / 16)));
    }

    .timeline-video-frame {
        position: relative;
        width: 100%;
        aspect-ratio: var(--media-aspect, 9 / 16);
        border-radius: 8px;
        overflow: hidden;
        border: 1px solid #D5DCE7;
        background: #0a0a0a;
    }

    .test-detail-page .timeline-video-frame {
        max-height: calc(100dvh - 280px);
        margin: 0 auto;
    }

    .timeline-video {
        width: 100%;
        height: 100%;
        background: #000;
        object-fit: contain;
    }

    .timeline-still {
        width: 100%;
        height: 100%;
        display: block;
        background: #000;
        object-fit: contain;
    }

    .touch-overlay-layer {
        position: absolute;
        inset: 0;
        pointer-events: none;
        overflow: hidden;
        z-index: 2;
    }

    .hierarchy-overlay-layer {
        position: absolute;
        inset: 0;
        overflow: hidden;
        pointer-events: auto;
        z-index: 3;
    }

    .hierarchy-hints-layer {
        position: absolute;
        inset: 0;
        pointer-events: none;
        z-index: 1;
    }

    .hierarchy-hint-box {
        position: absolute;
        border: 1px solid rgba(175, 82, 222, 0.56);
        background: transparent;
        border-radius: 4px;
        box-shadow: none;
        opacity: 0.5;
    }

    .hierarchy-hint-box.is-hovered {
        border-color: rgba(175, 82, 222, 0.82);
        opacity: 0.72;
    }

    .hierarchy-hint-box.is-selected {
        border-color: rgba(175, 82, 222, 0.96);
        border-width: 2px;
        opacity: 0.92;
    }

    .touch-indicator {
        position: absolute;
        width: 24px;
        height: 24px;
        border-radius: 999px;
        border: 2px solid rgba(0, 122, 255, 0.98);
        background: rgba(0, 122, 255, 0.52);
        box-shadow: 0 0 0 1px rgba(0, 88, 194, 0.45), 0 6px 18px rgba(0, 56, 128, 0.32);
        transform: translate(-50%, -50%) scale(0.9);
        opacity: 0;
        transition: none;
        will-change: transform, opacity, left, top;
    }

    .hierarchy-highlight-box {
        position: absolute;
        border: 2px solid rgba(175, 82, 222, 0.96);
        background: transparent;
        box-shadow: 0 0 0 1px rgba(96, 34, 126, 0.34);
        border-radius: 5px;
        pointer-events: none;
    }

    .hierarchy-side-panel {
        width: min(300px, 30vw);
        min-width: 260px;
        display: flex;
        align-items: stretch;
        gap: 8px;
    }

    .hierarchy-side-panel.is-collapsed {
        width: 32px;
        min-width: 32px;
    }

    .hierarchy-side-panel[hidden] {
        display: none;
    }

    .hierarchy-side-toggle {
        border: 1px solid #CAD6E8;
        background: #F6F9FF;
        border-radius: 8px;
        color: #2D4365;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 0;
        width: 32px;
        height: 32px;
        flex: 0 0 auto;
    }

    .hierarchy-side-toggle:hover {
        background: #EDF3FF;
    }

    .hierarchy-side-toggle-icon {
        width: 14px;
        height: 14px;
        fill: currentColor;
        transition: transform 0.14s ease;
        transform: rotate(180deg);
    }

    .hierarchy-side-panel.is-collapsed .hierarchy-side-toggle-icon {
        transform: rotate(0deg);
    }

    .hierarchy-side-panel.is-collapsed .hierarchy-side-toggle {
        width: 32px;
    }

    .hierarchy-side-body {
        flex: 1;
        min-width: 0;
        border: 1px solid #D9E4F4;
        background: #F9FBFF;
        border-radius: 9px;
        padding: 8px;
        display: grid;
        grid-template-rows: auto auto auto minmax(0, 1fr);
        gap: 8px;
        overflow: hidden;
    }

    .hierarchy-side-title {
        font-size: 0.73rem;
        font-weight: 700;
        color: #5A4572;
        letter-spacing: 0.05em;
        text-transform: uppercase;
    }

    .hierarchy-candidate-item {
        width: 100%;
        display: block;
        text-align: left;
        border: 1px solid transparent;
        border-radius: 7px;
        background: transparent;
        padding: 7px 8px;
        cursor: pointer;
    }

    .hierarchy-candidate-item:hover,
    .hierarchy-candidate-item:focus {
        background: #F4EBFC;
        border-color: #D6BEE9;
        outline: none;
    }

    .hierarchy-candidate-item.is-selected {
        background: #EADBFA;
        border-color: #B98CDB;
    }

    .hierarchy-candidate-item.is-hovered {
        background: #F2E6FC;
        border-color: #CCABEA;
    }

    .hierarchy-candidate-title {
        display: block;
        color: #2F2440;
        font-size: 0.78rem;
        font-weight: 600;
        line-height: 1.25;
    }

    .hierarchy-candidate-frame {
        display: block;
        color: #6C5A84;
        font-size: 0.71rem;
        margin-top: 2px;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
    }

    .hierarchy-candidate-panel {
        border: 1px solid #E2D7EE;
        background: #FEFCFF;
        border-radius: 8px;
        padding: 8px;
        display: grid;
        grid-template-rows: auto auto minmax(0, 1fr);
        gap: 6px;
        min-height: 120px;
    }

    .hierarchy-candidate-panel[hidden] {
        display: none;
    }

    .hierarchy-candidate-heading {
        font-size: 0.74rem;
        font-weight: 700;
        color: #5A4572;
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }

    .hierarchy-candidate-empty {
        font-size: 0.73rem;
        color: #736088;
        line-height: 1.35;
    }

    .hierarchy-candidate-empty[hidden] {
        display: none;
    }

    .hierarchy-candidate-list {
        min-height: 0;
        max-height: 180px;
        overflow: auto;
        display: grid;
        gap: 4px;
    }

    .hierarchy-toolbar {
        border: 1px solid #E5D9F0;
        background: #F9F4FD;
        border-radius: 8px;
        padding: 6px 9px;
        display: flex;
        align-items: center;
        gap: 8px;
        color: #452C5B;
        font-size: 0.78rem;
    }

    .hierarchy-toolbar-dot {
        width: 8px;
        height: 8px;
        border-radius: 999px;
        background: #AF52DE;
        box-shadow: 0 0 0 2px rgba(175, 82, 222, 0.26);
        flex: 0 0 auto;
    }

    .hierarchy-inspector {
        border: 1px solid #E6DEEF;
        background: #FDFBFF;
        border-radius: 8px;
        padding: 10px 11px;
        display: grid;
        gap: 6px;
    }

    .hierarchy-inspector-title {
        font-size: 0.84rem;
        font-weight: 700;
        color: #2B1E39;
    }

    .hierarchy-inspector-subtitle {
        font-size: 0.74rem;
        color: #66557D;
    }

    .hierarchy-inspector-properties {
        max-height: min(280px, 34vh);
        overflow: auto;
        border-top: 1px solid #ECE3F5;
        padding-top: 6px;
    }

    .hierarchy-prop-row {
        display: grid;
        grid-template-columns: minmax(92px, auto) minmax(0, 1fr);
        align-items: start;
        gap: 8px;
        font-size: 0.73rem;
        padding: 2px 0;
    }

    .hierarchy-prop-key {
        color: #6E5D85;
        font-weight: 600;
        text-align: right;
    }

    .hierarchy-prop-value {
        color: #2E2642;
        word-break: break-word;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
    }

    .hierarchy-prop-value.path {
        line-height: 1.4;
        white-space: pre-wrap;
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
            grid-template-columns: 1fr;
            align-items: stretch;
        }

        .hierarchy-side-panel {
            width: 100%;
            min-width: 0;
        }

        .test-detail-page .test-detail-shell {
            gap: 6px;
            padding: 8px;
        }

        .test-detail-page .test-header-compact {
            grid-template-columns: auto 1fr;
            align-items: start;
            row-gap: 6px;
        }

        .test-detail-page .test-title-compact {
            max-width: 100%;
        }

        .test-detail-page .test-title-group {
            grid-column: 1 / -1;
            justify-self: start;
            text-align: left;
        }

        .test-detail-page .test-title-row {
            justify-content: flex-start;
        }

        .test-detail-page .test-subtitle {
            max-width: 100%;
        }

        .test-detail-page .test-header-spacer {
            display: none;
        }

        .test-detail-page .timeline-video-layout {
            grid-template-columns: 1fr;
            grid-template-rows: minmax(0, 1fr) auto;
            gap: 10px;
        }

        .test-detail-page .timeline-video-card {
            width: min(100%, 300px, calc((100dvh - 460px) * var(--media-aspect, 9 / 16)));
        }

        .test-detail-page .timeline-video-frame {
            max-height: calc(100dvh - 460px);
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

        .test-subtitle {
            color: #AEBAD0;
        }

        .test-back-link {
            color: #E1E8F5;
            border-color: #3C4A62;
            background: #1B2432;
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
            background: #2D5DAF;
            border-color: #90B3FF;
            box-shadow: inset 0 0 0 1px rgba(188, 214, 255, 0.35), 0 0 0 1px rgba(104, 154, 235, 0.35);
        }

        .timeline-event.timeline-context-active:not(.timeline-active) {
            background: #263A63;
            border-color: #5F7FAF;
        }

        .timeline-event.timeline-active-proxy:not(.timeline-active) {
            background: #345692;
            border-color: #7FA5E8;
            box-shadow: inset 0 0 0 1px rgba(186, 214, 255, 0.38);
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
            box-shadow: inset 0 0 0 1px rgba(255, 202, 211, 0.34), 0 0 0 1px rgba(180, 114, 128, 0.32);
        }

        .timeline-tree ul > li.timeline-node > .timeline-event.timeline-failure.timeline-active-proxy:not(.timeline-active),
        .timeline-tree ul > li.timeline-node > details > summary > .timeline-event.timeline-failure.timeline-active-proxy:not(.timeline-active) {
            background: #643641;
            border-color: #B27A86;
            box-shadow: inset 0 0 0 1px rgba(255, 188, 198, 0.35);
        }

        .timeline-event.timeline-failure .timeline-title {
            color: #ffbcc6;
        }

        .timeline-event.timeline-active .timeline-title,
        .timeline-event.timeline-active .timeline-time,
        .timeline-event.timeline-active .timeline-disclosure {
            color: #FFFFFF;
        }

        .timeline-event.timeline-interaction .timeline-time::before {
            background: #73A7FF;
            box-shadow: 0 0 0 2px rgba(115, 167, 255, 0.25);
        }

        .timeline-event.timeline-hierarchy .timeline-time::after {
            background: #C88BEE;
            box-shadow: 0 0 0 2px rgba(200, 139, 238, 0.28);
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

        .timeline-tree-action-btn {
            color: #E1E8F5;
            background-color: #253043;
            border-color: #4B5E80;
        }

        .timeline-tree-action-btn:hover {
            background-color: #2D3A52;
        }

        .timeline-button:hover {
            background-color: #575757;
        }

        .timeline-run-selector {
            color: #D8E2F0;
        }

        .timeline-run-select {
            background: #1F2734;
            border-color: #3A475B;
            color: #DDE6F7;
        }

        .timeline-attachment-link {
            background: #1F2734;
            border-color: #3A475B;
            color: #DDE6F7;
        }

        .timeline-attachment-link:hover {
            background: #273246;
            border-color: #516686;
        }

        .timeline-attachment-icon {
            background: #263750;
            border-color: #486489;
            color: #CAE0FF;
        }

        .timeline-attachment-inline {
            background: #1C2431;
            border-color: #3A475B;
        }

        .timeline-attachment-inline pre {
            color: #DDE6F7;
        }

        .attachment-preview-dialog {
            background: #171717;
            border-color: #424242;
            box-shadow: 0 24px 46px rgba(0, 0, 0, 0.55);
        }

        .attachment-preview-header {
            background: #1E2633;
            border-bottom-color: #424242;
        }

        .attachment-preview-title {
            color: #E6EEF9;
        }

        .attachment-preview-open,
        .attachment-preview-close {
            background: #253043;
            border-color: #4B5E80;
            color: #DCE6F8;
        }

        .attachment-preview-body {
            background: #111827;
        }

        .attachment-preview-frame {
            background: #111827;
        }

        .attachment-preview-empty {
            color: #B2BDD0;
        }

        .hierarchy-highlight-box {
            border-color: rgba(105, 193, 255, 0.98);
            background: transparent;
            box-shadow: 0 0 0 1px rgba(78, 150, 255, 0.5);
        }

        .hierarchy-hint-box {
            border-color: rgba(196, 133, 233, 0.42);
            background: transparent;
            box-shadow: none;
            opacity: 0.56;
        }

        .hierarchy-hint-box.is-hovered {
            border-color: rgba(205, 152, 239, 0.75);
            opacity: 0.74;
        }

        .hierarchy-hint-box.is-selected {
            border-color: rgba(213, 166, 242, 0.9);
            background: transparent;
            box-shadow: none;
            border-width: 2px;
            opacity: 0.92;
        }

        .hierarchy-side-toggle {
            background: #253043;
            border-color: #4B5E80;
            color: #DCE6F8;
        }

        .hierarchy-side-toggle:hover {
            background: #2D3A4F;
        }

        .hierarchy-side-body {
            background: #181D27;
            border-color: #3B4556;
        }

        .hierarchy-candidate-panel {
            background: #211A2B;
            border-color: #5A4D6C;
        }

        .hierarchy-candidate-heading {
            color: #D7C7E9;
        }

        .hierarchy-side-title {
            color: #CDB9DF;
        }

        .hierarchy-candidate-empty {
            color: #BAA9CC;
        }

        .hierarchy-candidate-item:hover,
        .hierarchy-candidate-item:focus {
            background: #352A44;
            border-color: #8068A0;
        }

        .hierarchy-candidate-item.is-selected {
            background: #4B3362;
            border-color: #A683C9;
        }

        .hierarchy-candidate-item.is-hovered {
            background: #3D2E53;
            border-color: #9277B5;
        }

        .hierarchy-candidate-title {
            color: #E7D8F5;
        }

        .hierarchy-candidate-frame {
            color: #BFA9D4;
        }

        .hierarchy-toolbar {
            background: #272132;
            border-color: #5A4D6C;
            color: #E2D5EE;
        }

        .hierarchy-toolbar-dot {
            background: #C88BEE;
            box-shadow: 0 0 0 2px rgba(200, 139, 238, 0.26);
        }

        .hierarchy-inspector {
            background: #1E2029;
            border-color: #4C495A;
        }

        .hierarchy-inspector-title {
            color: #ECE1F6;
        }

        .hierarchy-inspector-subtitle {
            color: #BFB0D0;
        }

        .hierarchy-inspector-properties {
            border-top-color: #454057;
        }

        .hierarchy-prop-key {
            color: #B9A8CC;
        }

        .hierarchy-prop-value {
            color: #ECE1F6;
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
