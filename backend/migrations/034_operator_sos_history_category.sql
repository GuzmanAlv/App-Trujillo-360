-- Include the operator's incident classification in the SOS history list.
ALTER FUNCTION trujillo.list_help(boolean) RENAME TO list_help_v33;
CREATE FUNCTION trujillo.list_help(p_operator boolean DEFAULT false) RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 RETURN QUERY
 SELECT CASE WHEN p_operator AND item->>'source'='sos' THEN
   jsonb_set(item,'{sos_case}',coalesce(item->'sos_case','{}'::jsonb) ||
     (SELECT jsonb_build_object('category',c.category,'place',c.place)
      FROM trujillo.sos_cases c WHERE c.id=(item->>'id')::uuid))
  ELSE item END
 FROM trujillo.list_help_v33(p_operator) AS item;
END; $$;
REVOKE ALL ON FUNCTION trujillo.list_help_v33(boolean),trujillo.list_help(boolean)
 FROM PUBLIC,anon,authenticated,trujillo_api;
GRANT EXECUTE ON FUNCTION trujillo.list_help(boolean) TO trujillo_api;
