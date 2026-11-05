-- 2026-11-05, owner said "yes hide it": 52 live listings with no real price (null, <= $15, or a fake
-- number such as 123 / 123456) were set to status 'hidden' (not deleted). Run by Claude via MCP.
-- live -> hidden fires no message trigger. Putting one back to 'live' re-runs the new-listing triggers.
-- To bring one back after the owner adds a price:  update listings set status='live' where ref='SY…';
update listings set status='hidden'
where status='live' and (price_usd is null or price_usd<=15 or price_usd in (123,1234,12345,123456,111,1111,999,9999));
-- hidden refs:
-- SY10269 SY10275 SY10296 SY10297 SY10312 SY10316 SY10318 SY10321 SY10322 SY10330 SY10331 SY10332 SY10333
-- SY10334 SY10335 SY10336 SY10337 SY10338 SY10339 SY10340 SY10341 SY10342 SY10353 SY10360 SY10362 SY10363
-- SY10365 SY10367 SY10368 SY10369 SY10370 SY10372 SY10373 SY10374 SY10375 SY10388 SY10389 SY10393 SY10413
-- SY10417 SY10432 SY10435 SY10453 SY10463 SY10468 SY10491 SY10495 SY10600 SY10636 SY10637 SY10638 SY10639
