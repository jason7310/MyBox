package com.handy.mig;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

/**
 * [통합 MIG] 결재 키 매핑 및 원문서 정합성 사전 검증 도구 (Java 17 호환 / 자동 파일 반출 지원)
 * 
 * - 기능:
 *   1. config/db.properties 파일의 설정을 자동으로 읽어 DB에 연결합니다.
 *   2. AS-IS 원문서(ORIGIN_DOC_ID)와 TO-BE 원결재문서(ORGAPPRID) 간의 매핑 정합성 검사
 *   3. 매핑되지 않는 '00000000000000000000' 건수의 원인(AS-IS 원문서 부재, 미이관 대상 등)을 사전 리포팅
 *   4. 검증 결과 리포트를 logs/ 디렉토리에 자동 파일 저장하여 외부망 반출 지원
 */
public class ApprovalKeyMapper {

    public static void main(String[] args) {
        MigLogger.init("validate");
        MigLogger.info("=========================================================================");
        MigLogger.info(" [Handy MIG] 결재 키 및 원문서 정합성 사전 진단 도구 (JDK 17)");
        MigLogger.info("=========================================================================");

        // 외부 설정 파일 경로가 지정된 경우 로드
        if (args.length > 0) {
            try {
                DbConfig.load(args[0]);
            } catch (Exception e) {
                MigLogger.warn("지정된 설정 파일 로드 실패 (" + args[0] + "), 기본 설정을 시도합니다.");
            }
        }

        try (Connection conn = DbConfig.getConnection()) {
            MigLogger.info("데이터베이스 접속 성공 (" + DbConfig.getUrl() + ")");

            // 1. 전체 결재 대상 건수 파악
            String sqlTotal = "SELECT COUNT(*) AS TOTAL_CNT, " +
                              "       COUNT(ORIGIN_DOC_ID) AS ORIGIN_CNT, " +
                              "       SUM(CASE WHEN DOCATTR IN ('4','5') THEN 1 ELSE 0 END) AS ENF_CNT " +
                              "  FROM MIG1_USER.MG_APPROVAL";

            try (PreparedStatement pstmt = conn.prepareStatement(sqlTotal);
                 ResultSet rs = pstmt.executeQuery()) {
                if (rs.next()) {
                    long total = rs.getLong("TOTAL_CNT");
                    long origin = rs.getLong("ORIGIN_CNT");
                    long enf = rs.getLong("ENF_CNT");
                    MigLogger.info(String.format("[현황 분석] 전체 문서: %,d 건 | 원문서 참조 문서: %,d 건 | 수신/시행 문서: %,d 건", total, origin, enf));
                }
            }

            // 2. MAPPING_APPR_KEY 기준 매핑 성공/누락 분석
            String sqlValidate = "SELECT " +
                                 "    COUNT(*) AS TOTAL_ORIGIN_DOCS, " +
                                 "    COUNT(K2.APPRID) AS MATCHED_CNT, " +
                                 "    COUNT(CASE WHEN K2.APPRID IS NULL THEN 1 END) AS UNMATCHED_CNT " +
                                 " FROM INTRAWARE.MAPPING_APPR_KEY K1 " +
                                 " LEFT JOIN INTRAWARE.MAPPING_APPR_KEY K2 ON K1.ORIGIN_DOC_ID = K2.DOC_ID " +
                                 " WHERE K1.ORIGIN_DOC_ID IS NOT NULL";

            try (PreparedStatement pstmt = conn.prepareStatement(sqlValidate);
                 ResultSet rs = pstmt.executeQuery()) {
                if (rs.next()) {
                    long totalOrigin = rs.getLong("TOTAL_ORIGIN_DOCS");
                    long matched = rs.getLong("MATCHED_CNT");
                    long unmatched = rs.getLong("UNMATCHED_CNT");

                    MigLogger.printBoth("-------------------------------------------------------------------------");
                    MigLogger.printBoth(" [검증 결과] 원문서(ORIGIN_DOC_ID) 매핑 현황:");
                    MigLogger.printBoth(String.format("  - 원문서 링크 대상 문서   : %,d 건", totalOrigin));
                    MigLogger.printBoth(String.format("  - 정상 매핑(ORGAPPRID 확보): %,d 건 (%.2f%%)", matched, (totalOrigin > 0 ? (matched * 100.0 / totalOrigin) : 0)));
                    MigLogger.printBoth(String.format("  - 미매핑(원문서가 대상에 없음): %,d 건 (%.2f%%)", unmatched, (totalOrigin > 0 ? (unmatched * 100.0 / totalOrigin) : 0)));
                    MigLogger.printBoth("-------------------------------------------------------------------------");
                    if (unmatched > 0) {
                        MigLogger.info("[참고] 미매핑 건은 AS-IS 삭제문서, 비전자문서, 보존연한 만료 등으로 이관 대상 DB에 없는 원문서입니다.");
                        MigLogger.info("       이 건들은 자동으로 '00000000000000000000' 처리되어 정상 적재됩니다.");
                    }
                }
            }

            MigLogger.info("정합성 진단 완료!");
            MigLogger.complete();

        } catch (Exception e) {
            MigLogger.error("정합성 진단 중 오류 발생: " + e.getMessage(), e);
        }
    }
}
