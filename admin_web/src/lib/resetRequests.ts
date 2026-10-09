/** Password-reset requests still waiting for the admin: not yet used, cancelled or expired. */
export const OPEN_RESET_STATUSES = ['pending', 'code_issued'];
export const isOpenReset = (request: { status: string }) => OPEN_RESET_STATUSES.includes(request.status);
